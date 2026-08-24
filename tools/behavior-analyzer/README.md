# behavior-analyzer — 바이너리 행동 종합 분석 툴

`disasm`이 뽑아둔 재료를 읽어, 앱이 실제로 어떻게 행동하는지를 한 장으로 요약한다.
라우트·읽는 요청 필드·필수 환경변수·인위적 지연·확률 분기·자원 소모·공격 판별 단서를 카테고리별로 정리해 `report.txt`와 `findings.json`으로 낸다.

`disasm`이 원재료를, `assembly-prettier`가 문자열을 복원한다면, 이 툴은 그 위에서 **"그래서 이 바이너리가 뭘 하는가"**를 종합한다.

## 왜 필요한가

바이너리 하나에서 봐야 할 게 흩어져 있다. 라우트는 `main`에, 읽는 헤더는 핸들러에, 지연·확률은 여기저기, 차단 문자열은 hex로 쪼개진 채 pseudocode에 박혀 있다.
`disasm` 출력 디렉토리를 열어 파일 수십 개를 일일이 훑는 대신, 이 툴이 한 번에 긁어 한 장으로 정리한다.

특히 악성 트래픽 판별은 미리 뭘 검사할지 알 수 없다. 작년엔 User-Agent였지만 올해는 커스텀 헤더나 쿼리일 수 있다.
그래서 "UA를 찾자"가 아니라 **핸들러가 읽는 요청 필드를 전부 나열하는** 식으로 접근한다. 앱이 어떤 필드를 읽으려면 그 이름이 코드에 문자열로 박혀야 하므로, 필드가 뭘로 바뀌든 목록에 드러난다.

## 사용법

입력은 `disasm`이 만든 출력 디렉토리다. (`disassembly/disassembly/<바이너리>-<타임스탬프>/`)

```bash
./analyze <disasm_출력_디렉토리> [-o 출력디렉토리]
```

예:

```bash
cd ../disassembly && ./disasm ../../provided/stress
./analyze ../disassembly/disassembly/stress-20260824.../
```

`-o`를 생략하면 입력 디렉토리 안에 `report.txt`·`findings.json`을 쓴다.

## 탐지 카테고리

| 카테고리 | 무엇을 | 근거 |
|---|---|---|
| 메타 | Go 버전·모듈·빌드 플래그 | `00_buildinfo.txt` |
| 필수 환경변수 | `os.Getenv`/`LookupEnv` 키 | objdump/pseudocode |
| 라우트 | `r.GET/POST/PUT/DELETE` + 경로 | objdump/strings |
| 읽는 요청 필드 | `Query`/`GetHeader`/`Header.Get`/`Param`/`Bind` | objdump/pseudocode |
| 응답 | `http.Status…`·`AbortWithStatus` | objdump/pseudocode |
| 인위적 지연 | `time.Sleep`/`After` + Duration 상수 | objdump/pseudocode |
| 확률 분기 | `rand.Intn`/`Float64` + 임계 상수(0.4 등) | objdump/pseudocode |
| 자원 소모 | burn/spin 류 함수·핫패스 crypto | symbols/objdump |
| 공격 판별 | 문자열 비교 + 복원된 비교값 + 의심 토큰 | prettified/strings |
| 외부 연동 | S3·RDS·SQL·크레덴셜 env | 종합 |

`report.txt`는 카테고리별 고정폭 텍스트 리포트이고, `findings.json`은 같은 내용을 기계가 읽을 수 있게 담은 데이터다. 복원된 비교 문자열(`== "Attacker-Bot"` 등)은 `string-compare` 항목에 근거 파일 경로와 함께 들어간다.

## prettify와 이어서

공격 판별 문자열은 hex 청크로 쪼개져 있어 raw pseudocode만으로는 안 보인다.
`disasm` 출력 안에 `assembly-prettier`로 만든 `prettified/*.readable.c`가 함께 있으면, 이 툴이 거기서 복원된 비교값(`== "..."`)을 읽어 공격 단서로 올린다.
그래서 순서는 `disasm` → `prettify`(pseudocode를 readable.c로) → `analyze`가 가장 풍부하다.

웹 툴(`task3-web-tool`)에서는 이 세 단계가 한 번에 돌아간다. 바이너리를 올리고 "행동 분석"을 켜면 disasm·prettify·analyze가 이어서 실행되고 `report.txt`가 결과 zip에 담긴다.

## 한계

- 정적 분석이라 **런타임에만 정해지는 값**(원격 설정, 응답으로 받은 임계치)은 못 잡는다. 코드에 리터럴로 박힌 것만 나온다.
- 확률 임계 상수는 "후보"로 표시한다. `rand.Float64()` 근처의 `0.x` 값을 모으는 방식이라, 무관한 상수가 섞일 수 있다. 최종 판단은 근거 파일을 본다.
- 문자열이 hex 청크가 아니라 스택에 바이트로 흩어져 조립되는 경우는 `prettify`가 못 푸므로 여기서도 안 나온다. 그런 건 `02_strings.txt`나 pseudocode를 직접 본다.
- 카테고리 매칭은 gin 기준이다. 다른 웹 프레임워크면 요청 필드 정규식을 손봐야 한다.

## 요구 환경

Python 3만 있으면 된다. 외부 패키지가 없어 CloudShell에서도 그대로 돌아간다.

## 구성

- `analyze` — 탐지·리포트 로직 전부가 담긴 Python 스크립트
