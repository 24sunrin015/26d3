# assembly-prettier — pseudocode 문자열 비교 복원 툴

Ghidra가 뽑은 Go pseudocode를 사람이 읽을 수 있게 다듬는다.
특히 문자열 비교가 정수 hex 비교로 쪼개져 있는 부분을 원래 문자열로 되돌린다.

## 왜 필요한가

Go 컴파일러는 짧은 문자열 리터럴 비교를 정수 청크 비교로 바꿔버린다.
그래서 Ghidra pseudocode에는 이런 게 그대로 남는다.

```c
if (((sVar9.len == 10) && (*(int *)sVar9.str == 0x617474612d746f62)) &&
   ((short)*(int *)((int)sVar9.str + 8) == 0x6b63)) {
```

이 hex 두 개를 리틀엔디안 ASCII로 풀면 `"bot-atta"` + `"ck"`, 이어붙이면 `"bot-attack"`이다.
길이 검사값 `== 10`이 복원한 글자 수와 맞으니 확실하다.
결국 저 조건은 `if (User-Agent == "bot-attack")`을 검사하는 코드다.

악성 트래픽 판별 로직이 대개 이런 형태로 숨어 있다.
`disassembly`로 pseudocode까지 뽑고 나면, 이 툴이 그중 문자열 비교를 사람 말로 바꿔준다.

## 사용법

입력은 `disassembly`가 뽑아낸 pseudocode `.c` 파일이다. **바이너리(`provided/user` 등)를 직접 넣으면 안 된다.**
바이너리를 넣으면 알아보기 힘든 텍스트가 그대로 쏟아지고 파일이 수백 MB로 불어난다.
그래서 툴은 ELF 매직이나 NUL 바이트가 보이면 입력을 거부한다.

```bash
./prettify <pseudocode.c> [-o 출력디렉토리]
```

예:

```bash
./prettify ../disassembly/disassembly/user-.../pseudocode/PostEmployee.c
```

파일 하나를 받아 세 가지를 만든다. 출력은 `-o`를 안 주면 `./prettified/`에 쌓이고,
파일명은 `<이름>-<YYYYMMDD-HHMMSS>.{확장자}`로 붙는다.

- `<이름>-<타임스탬프>.annotated.c` — 원본을 그대로 두고 복원한 문자열을 주석으로 붙인다
- `<이름>-<타임스탬프>.readable.c` — hex를 문자열 리터럴로 직접 치환한다
- `<이름>-<타임스탬프>.py` — C 문법을 파이썬처럼 다듬어 인덴트로 흐름을 보여준다

실행하면 복원된 문자열 비교 목록도 터미널에 요약해 보여준다.

```
복원된 문자열 비교:
  sVar9 == "bot-attack"
```

## 파이썬 변환본은 뭔가

`.py`는 Ghidra의 C 유사 문법을 파이썬 문법에 맞춰 기계적으로 옮긴 읽기 보조본이다.
타입 캐스트를 지우고, `&&`를 `and`로, `->`를 `.`으로 바꾸고, 중괄호 깊이를 인덴트로 재구성한다.
`LAB_0078be68` 같은 긴 라벨은 `label_1`로 줄이고, `goto`에는 점프 방향(위로 반복 / 아래로 건너뜀)을 주석으로 단다.
그러면 `if (User-Agent == "bot-attack"): ... return` 꼴로 조건과 분기가 눈에 들어온다.

실행되는 파이썬은 아니다. 포인터·런타임 호출은 그대로 남으니 흐름 파악용으로만 쓴다.
정확한 로직은 `.readable.c`가 낫고, `.go` 재구성이 필요하면 그걸 Q Developer에 넘긴다.

## 두 가지 복원

**라인 단위** — 한 줄에 있는 hex 하나하나를 ASCII로 풀어 그 줄 끝에 주석을 단다.
`0x617474612d746f62` 옆에 `// "bot-atta"`가 붙는 식이다.

**블록 단위** — `if` 조건 하나를 통째로 읽어, 같은 변수(`sVar9.str`)에 흩어진 청크를 offset 순으로 이어붙인다.
`str+0`의 `"bot-atta"`와 `str+8`의 `"ck"`를 합쳐 `sVar9 == "bot-attack"` 한 줄로 요약하고, `if` 앞에 `// [복원]`으로 끼워넣는다.
길이 검사값과 복원 길이가 다르면 `(※ len 불일치)`를 달아 부분 검사임을 알린다.

## 한계

- ASCII로 안 풀리는 hex(주소·플래그·이진 상수)는 건드리지 않는다. 오탐을 막으려고 출력 가능한 문자로만 이뤄진 값만 복원한다.
- 문자열이 스택에 바이트로 흩어져 조립되는 패턴(청크 비교가 아닌 경우)은 아직 못 잡는다. 그런 건 `disassembly`의 `02_strings.txt`나 pseudocode를 직접 봐야 한다.
- `.py`는 중괄호를 인덴트로 바꾸고 라벨·goto를 정리해 분기를 보여준다. goto가 서로 얽힌 복잡한 흐름을 완전히 구조화된 반복/분기로 풀어내진 못한다. 거기까진 Q Developer에 맡기는 편이 낫다.
- 변수명(`sVar9`, `local_20` 등)은 Ghidra가 붙인 그대로 둔다. 임의로 개명하면 원본 pseudocode와 대조가 어려워지기 때문이다.

## 요구 환경

Python 3만 있으면 된다. 외부 패키지가 필요 없어 CloudShell에서도 그대로 돌아간다.

## disassembly와 이어서

1. `disassembly/disasm`으로 바이너리에서 pseudocode를 뽑는다. (`cd ../disassembly && ./disasm ../../provided/product`)
2. 거기서 나온 핸들러 pseudocode(`PostUser.c`, `PostProduct.c` 등)를 이 툴에 넣는다. 바이너리를 바로 넣는 게 아니다.
3. 요약에 뜬 문자열이 악성 판별에 쓰는 값이다. WAF 차단 규칙(User-Agent 등)에 그대로 반영한다.
4. 흐름 해석이나 `.go` 재구성이 더 필요하면 `.readable.c`를 Q Developer에 붙여넣는다.

## 구성

- `prettify` — 복원 로직 전부가 담긴 Python 스크립트
