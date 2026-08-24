# 2025 실측 분석

`0923.zip`의 ALB access log 209개를 집계했다. API별로 `request_processing_time + target_processing_time + response_processing_time`을 더하고, 2xx와 함께 user/product는 0.2초, stress는 1초를 기준으로 계산했다. 가용성 기준은 5초다.

| API | 정상 후보 | availability | performance | 실패 내역 |
| --- | ---: | ---: | ---: | --- |
| user | 28,501 | 100.00% | 77.11% | 없음 |
| product | 76,508 | 99.99% | 78.95% | 400 5건, 404 1건 |
| stress | 43,339 | 67.14% | 51.24% | 400 1건, 460 2,699건, 504 3,744건 |

user와 product의 403은 이메일·비정상 요청을 WAF가 막은 4,500건씩이라 정상 후보에서 뺐다. 세 API 모두 점수의 30% gate는 넘었지만, 당시 병목은 stress였다. 5초 안에 끝난 비율도 67.14%였고 1초 SLO 안에 들어온 비율은 51.24%였다.

## 2025 점수 차이

ALB 로그로 계산한 추정 점수는 28.0/40이지만, 실제 점수는 27.5/40이었다. 차이 0.5점은 stress performance의 50% 구간으로 본다.

| 항목 | 점수 | 계산 |
| --- | ---: | --- |
| 비정상 요청 | 4.0 | 이메일 검사·악성 트래픽 만점 가정 |
| availability | 9.0 | user 4.0, product 4.0, stress 1.0 |
| performance | 4.0 | user 1.5, product 1.5, stress 1.0 |
| instance 비용 | 11.0 | 입력값 |
| ALB 로그 기준 합계 | 28.0 | 40점 만점 |
| 실제 점수 | 27.5 | stress performance 0.5점 차이 |

stress performance는 ALB 기준 51.24%로 50% 문턱보다 1.24%p 높을 뿐이었다. stress 2xx 중 497건, 전체 stress 요청의 1.15%가 0.9~1.0초 구간에 있었다. 실제 채점은 클라이언트 도착 기준이므로 CloudFront와 인터넷 구간 지연이 더해지면서 50% 아래로 내려갔을 가능성이 가장 높다.

이 값은 ALB 관측치다. 실제 채점은 클라이언트 도착 기준이라 CloudFront와 인터넷 구간은 빠져 있다. 그래도 2025 시스템이 stress 구간에서 가장 먼저 흔들렸다는 비교 기준으로 쓸 수 있다.

2026에서는 `2026-image-heavy`의 stress peak/spike 19.01/22.18 RPS보다 높은 `2026-stress-heavy` 30.38/33.75 RPS를 사용한다. `collapse-test`는 36 RPS와 length 200만으로 붕괴선만 따로 본다.

## 근거

- `extracted/2025-WSK-TP-3과제-덤프자료/로그/0923.zip`: ALB access log 원본
- `2025_task.md`: API별 5초 가용성 및 SLO
