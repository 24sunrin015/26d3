FROM golang:1.24-alpine AS build

WORKDIR /src
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o hedger main.go

FROM public.ecr.aws/amazonlinux/amazonlinux:2023

COPY --from=build /src/hedger /hedger
EXPOSE 8080
ENTRYPOINT ["/hedger"]
