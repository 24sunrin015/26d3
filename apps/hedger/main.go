package main

import (
	"context"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const hedgeDelay = 40 * time.Millisecond

var client = &http.Client{
	Transport: &http.Transport{
		MaxIdleConns:        100,
		MaxIdleConnsPerHost: 100,
		IdleConnTimeout:     90 * time.Second,
	},
}

type attempt struct {
	response *http.Response
	err      error
}

func main() {
	backends := map[string]string{
		"/v1/user":    requiredEnv("USER_BACKEND"),
		"/v1/product": requiredEnv("PRODUCT_BACKEND"),
	}

	http.HandleFunc("/healthcheck", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		backend, ok := backends[r.URL.Path]
		if !ok || r.Method != http.MethodGet {
			http.NotFound(w, r)
			return
		}
		hedge(w, r, backend)
	})

	log.Fatal(http.ListenAndServe(":8080", nil))
}

func requiredEnv(name string) string {
	value := os.Getenv(name)
	if value == "" {
		log.Fatalf("%s is required", name)
	}
	return strings.TrimRight(value, "/")
}

func hedge(w http.ResponseWriter, r *http.Request, backend string) {
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	results := make(chan attempt, 2)
	go send(ctx, backend, r, results)

	timer := time.NewTimer(hedgeDelay)
	defer timer.Stop()
	attempts := 1
	completed := 0

	for {
		select {
		case result := <-results:
			completed++
			if result.err == nil {
				defer result.response.Body.Close()
				copyResponse(w, result.response)
				return
			}
			if attempts == 1 {
				attempts++
				if !timer.Stop() {
					select {
					case <-timer.C:
					default:
					}
				}
				go send(ctx, backend, r, results)
				continue
			}
			if completed == attempts {
				http.Error(w, "upstream unavailable", http.StatusBadGateway)
				return
			}
		case <-timer.C:
			if attempts == 1 {
				attempts++
				go send(ctx, backend, r, results)
			}
		}
	}
}

func send(ctx context.Context, backend string, original *http.Request, results chan<- attempt) {
	target, err := url.Parse(backend + original.URL.RequestURI())
	if err != nil {
		results <- attempt{err: err}
		return
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target.String(), nil)
	if err != nil {
		results <- attempt{err: err}
		return
	}
	req.Header = original.Header.Clone()
	req.Header.Del("Connection")
	req.Header.Del("Proxy-Connection")
	req.Header.Del("Keep-Alive")
	req.Header.Del("Transfer-Encoding")
	req.Header.Del("Upgrade")
	req.Host = target.Host

	response, err := client.Do(req)
	results <- attempt{response: response, err: err}
}

func copyResponse(w http.ResponseWriter, response *http.Response) {
	for key, values := range response.Header {
		if key == "Connection" || key == "Transfer-Encoding" {
			continue
		}
		for _, value := range values {
			w.Header().Add(key, value)
		}
	}
	w.WriteHeader(response.StatusCode)
	_, _ = io.Copy(w, response.Body)
}
