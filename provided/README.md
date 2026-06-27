# provided/ — 앱 바이너리 (user / product / stress)

이 디렉토리에는 현장에서 지급받는 앱 바이너리를 둔다. **바이너리 자체는 git에 올리지 않는다**(`.gitignore` 처리).

## 채울 파일

| 파일 | 설명 |
|---|---|
| `user` | 사용자 API (Go, linux/amd64) |
| `product` | 제품 API + 이미지 업로드 (Go, linux/amd64) |
| `stress` | 부하 발생 API (Go, linux/amd64) |

## 어디서 얻나

- **훈련**: `task3-author`에서 `make build` 후 `make publish`로 여기에 복사된다.
- **현장**: 경기 시작 10분 전 지급되는 바이너리를 여기에 넣는다.

세 파일이 모두 있어야 `make up`(인프라 반영)이 진행된다. 없으면 막힌다.
