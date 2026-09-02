# swrly × Claude Code Skills — 계획서

이 문서는 `swrly`에 Claude Code 스킬(`.claude/skills/*`)을 얹어, 사용자가
자기 Flutter 프로젝트에서 `/swrly-init`, `/swrly-refactor` 같은 명령으로
스캐폴딩 · 마이그레이션 · 리팩토링을 반복 가능한 형태로 수행하도록 만드는
작업의 **방향성**만 정리한다. 실제 구현은 이후 별도 태스크로 진행.

---

## 1. 왜 스킬인가

`swrly`는 "적용하는 순간"의 결정이 많은 라이브러리다:

- 어떤 상태관리와 공존하는가 (Bloc / Provider / Riverpod / Hooks / plain)
- 어디까지 `swrly`로 옮길 것인가 (전체 마이그레이션 vs 서버 상태만)
- `queryKey` 네이밍 컨벤션, `Query`/`QueryFamily` 정의 배치
- `staleTime` / `cacheTime` 초기값
- `MutationBuilder` + `onMutate` optimistic 패턴 도입 여부

이 결정들은 README에 설명돼 있지만, 사용자 코드에 **직접 적용**하려면
결국 사람이 매번 판단해야 한다. 스킬은 이 결정 트리를 코드화해 재사용
가능한 형태로 제공한다.

---

## 2. 지원 범위: 상태관리 매트릭스

현재 `swrly` 자체가 지원/미지원인 항목을 먼저 못박는다.

| 상태관리 | 현재 상태 | 스킬 지원 계획 |
|---|---|---|
| **없음 (StatefulWidget + setState)** | 예제 있음 (`example/lib/main.dart`) | ✅ 1순위 — 진입 장벽 가장 낮음 |
| **Provider** | 직접 통합 없음 (그냥 같이 씀) | ✅ 1순위 — 국내 레거시 프로젝트 다수 |
| **Riverpod** | 직접 통합 없음. 로드맵의 `AsyncValue` 브릿지는 v0.5 예정 | ✅ 1순위 — 사용자 다수 |
| **Bloc / Cubit** | 직접 통합 없음. 로드맵의 `AsyncValue` 브릿지는 v0.5 예정 | ✅ 1순위 |
| **flutter_hooks** | 별도 `swrly_hooks` 컴패니언 패키지가 지원 (core는 여전히 의존 없음) | ✅ 스킬 대응 — `flutter_hooks` 감지 시 `flutter pub add swrly_hooks` |
| **GetX** | 미지원 | ❌ 초기 범위 제외 (사용자 요청이 쌓이면 추가) |

**핵심 원칙**: 스킬이 만들어내는 코드는 라이브러리가 **실제로 지원하는
API만** 사용한다.

**hook에 대한 명시적 결정** (v2 — PR #13/#14 검증 반영): `swrly` core는
`flutter_hooks`를 의존성으로 갖지 않는다. 그 위에 얹는 `useSwrlyQuery` /
`useSwrlyMutation`은 **별도 컴패니언 패키지 `swrly_hooks`** 로 배포한다
(`flutter_bloc` / `hooks_riverpod` 관례와 동일).

이유:

- Dart는 npm-style peer dep가 없어 core에 `flutter_hooks`를 하드 넣으면 훅 미사용자에게 강제된다 → 컴패니언 분리로 해결
- 자체 hook 런타임 구현은 조합성(compositionality) 파괴 → 금지 결정 유지
- PR #13 초기에는 "정본 스니펫" 전략을 채택했으나, Codex 리뷰가 그 짧은 스니펫에서만 3개 실전 버그(subscriber 미등록, unhandled async, key hash 충돌)를 발견 → 라이브러리가 캡슐화해야 할 경계라는 게 증명됨. PR #14에서 컴패니언 패키지로 이관

`swrly-init` / `swrly-refactor-hooks` 스킬은 `flutter_hooks`가 pubspec에
있으면 `flutter pub add swrly_hooks`를 실행한다 (기존 "스니펫 복사" 스텝은
제거됨).

---

## 3. 스킬 목록 (초안)

`.claude/skills/` 아래에 각 스킬을 폴더로 둔다. `SKILL.md`에 트리거·인자·
행동을 명세, 필요한 참조 자료는 같은 폴더에 assets로.

### 3.1 `swrly-init` — 신규/기존 Flutter 프로젝트에 swrly 도입

**트리거**: "swrly 세팅해줘", "이 프로젝트에 swrly 붙여줘", `/swrly-init`

**입력 결정 트리** (스킬이 사용자에게 물어보거나 프로젝트에서 자동 감지):

1. 프로젝트에 이미 `swrly`가 있는가? (`pubspec.yaml` 확인) → 있으면 조기 종료 + 업그레이드 안내
2. 상태관리 감지: `pubspec.yaml`의 `flutter_bloc` / `provider` / `flutter_riverpod` / `flutter_hooks` 유무
3. 감지 실패 or 복수 → 사용자에게 확인
4. HTTP 클라이언트 감지: `dio` / `http` / `chopper` / GraphQL / Firebase → `queryFn` 예제에 반영
5. 프로젝트 규모: `lib/` 파일 수로 대략 판단 → 소규모면 인라인 정의, 중대형이면 `lib/queries/` 폴더 생성 제안

**출력 (프로젝트에 실제로 만드는 것)**:

- `lib/queries/` (또는 사용자 지정 위치)에 `Query` / `QueryFamily` 정의 파일 초기 골격
- `main.dart`에 `QueryClient.instance` 사용 예 하나 (선택적으로 `defaultRetry` 등 클라이언트 초기 설정)
- README 조각: `queryKey` 컨벤션 안내, "언제 `swrly`, 언제 상태관리" 규칙 (섹션 5 참고)
- 상태관리별 최소 통합 스니펫 하나 (섹션 4의 예제로 링크)

**하지 않는 것**: 기존 코드에는 손대지 않는다. 도입만.

---

### 3.2 `swrly-refactor` — 기존 코드를 swrly로 옮기기

리팩토링은 원본 코드가 어떤 패턴이냐에 따라 완전히 달라진다. 스킬 하나가
모든 걸 감당하는 대신, **서브 스킬**로 분리하거나 스킬 내부에서 분기한다.

#### 3.2.1 `FutureBuilder` → `QueryBuilder`

- 가장 안전. 1:1 매핑에 가깝다.
- 스킬이 파일을 스캔해 `FutureBuilder` 사용처를 목록화 → 각 케이스별로:
  - `future:` 표현식이 순수 함수 호출인지 확인 (side effect가 build 안에 있으면 경고)
  - `queryKey` 후보 제안 (호출 시그니처에서 유도)
  - `staleTime` 초기값 제안 (스킬은 30초 등 보수적 기본값 + 사용자 확인)
  - diff 형태로 제안 후 사용자 승인 → 적용
- **주의점 문서화**: `FutureBuilder`의 rebuild-마다-fetch 동작을 의도적으로 쓰던 곳은 옮기지 않는다.

#### 3.2.2 `StatefulWidget` + `initState`에서 fetch → `QueryBuilder` / `Query`

- 흔한 패턴: `initState`에서 `fetchX()` 호출 → `setState`로 `_data`/`_loading`/`_error` 관리
- 스킬 로직:
  - `_data`, `_loading`, `_error` 삼종 세트 감지
  - `dispose`에서 취소 로직 있는지 확인 (있으면 v0.4 cancellation 랜딩 전까지 경고)
  - 리스트/상세 페이지면 `QueryFamily` 제안, 단일이면 `Query` + `QueryBuilder`
  - 위젯이 `Stateless`로 승격 가능한지 판단 → 가능하면 승격까지 diff에 포함

#### 3.2.3 상태관리 라이브러리별 리팩토링

각각 다른 서브 스킬로:

**`swrly-refactor-provider`**:
- `ChangeNotifier` 안에 서버 fetch/loading/error 필드가 있으면 → 그 부분만 `Query`로 발라내기
- `ChangeNotifier`는 클라이언트 상태(폼, 토글)만 남긴다
- 사용처 (`Consumer` / `context.watch`)는 필요 부분만 `QueryBuilder`로 대체 제안

**`swrly-refactor-riverpod`**:
- `FutureProvider` / `FutureProvider.family` / `AsyncNotifier`에서 **stale/refetch 수기 관리** 부분 감지
  → `Query` / `QueryFamily`로 이관 제안 (README의 비교표 논리를 스킬에 인코딩)
- `ref.invalidate` → `query.invalidate()` 매핑
- **경계 원칙**: 순수 클라이언트 상태는 Riverpod 유지. swrly가 Riverpod을 대체하는 게 아니라 서버 상태만 흡수.
- v0.5 `AsyncValue` 브릿지 랜딩 전까지 스킬은 "두 세계를 병렬로 두는" 형태로 안내

**`swrly-refactor-bloc`**:
- `Bloc`/`Cubit`이 서버 fetch까지 담당하는 경우가 대부분 → repository 계층에 `Query.fetch()` 삽입
- `Bloc`의 loading/success/error state는 `swrly`가 제공하는 `QueryState`로 대체 가능한지 판단
- 완전 대체가 어색한 경우 (예: 여러 이벤트가 얽힌 state machine) → repository 레이어만 `swrly`로, Bloc은 유지 안내

**`swrly-refactor-hooks`**:
- core는 훅을 제공하지 않는다는 결정, **컴패니언 패키지 `swrly_hooks`가 지원한다는 결정** 두 개를 스킬이 반영한다.
- `flutter_hooks`를 이미 쓰는 프로젝트에서 서버 fetch를 하는 `useState`/`useEffect` 조합을 감지 → **`flutter pub add swrly_hooks` 실행** → `useSwrlyQuery` 사용하도록 리팩토링.
- 스킬은 `flutter_hooks`가 pubspec에 없는 프로젝트에는 자기 도입을 강요하지 않고, 대신 `swrly-refactor-stateful`로 자연스럽게 안내.

#### 3.2.4 `swrly-refactor-spaghetti` — 상태관리 없이 엉킨 코드

- 대상: 화면 위젯이 직접 http 콜을 하고, `_isLoading` `bool` 여러 개가 겹치고, 페이지 이동 시마다 재요청하는 코드
- 스킬 접근:
  1. **먼저 지도부터** — fetch 지점을 모두 리스트업해 사용자에게 보여준다 (한 번에 다 바꾸지 않는다)
  2. 사용자와 함께 우선순위 결정 (재사용 많은 것부터, 화면 하나부터)
  3. 화면 단위로 반복: fetch 추출 → `Query` 정의 → 위젯 교체 → 테스트/실행 확인
  4. 각 스텝은 revert 가능한 단일 커밋 크기로

- 안티 패턴: 스킬이 대규모 diff를 한 번에 만들지 않는다. `swrly`는 서버 상태 캐시일 뿐이고, 전면 재작성 도구가 아니라는 걸 사용자에게 명시.

---

### 3.3 부가 스킬 후보 (2순위)

- **`swrly-add-query`** — 기존 프로젝트에 새 쿼리 하나 추가 (컨벤션 준수 강제)
- **`swrly-add-mutation`** — `MutationBuilder` + optimistic + rollback 템플릿
- **`swrly-audit`** — 프로젝트 전체 스캔해 안티패턴 리포트
  - inline closure `queryFn` (README의 "왜 인라인은 안 되나" 참고)
  - `queryKey`가 문자열 하드코딩 (typo 시 silent miss)
  - `staleTime` 미지정
  - 커스텀 객체를 키에 그대로 (structural equality 이슈)
- **`swrly-upgrade`** — 마이너 버전 마이그레이션 (CHANGELOG 기반)

---

## 4. `example/` 확장 계획 — 상태관리별 Best Practice

현재 `example/lib/`는 `main.dart` 하나 + `stress/` 스트레스 테스트. 스킬이
"이 패턴을 따라 만든다"고 참조할 **정본 예제**가 필요하다.

제안 구조:

```
example/
  lib/
    main.dart                     # 현재 예제 (baseline, 상태관리 없음)
    patterns/
      plain/                      # StatefulWidget only — 지금 main.dart를 여기로
        posts_screen.dart
      provider/
        posts_screen.dart
        posts_notifier.dart       # 클라이언트 상태만 담당
      riverpod/
        posts_screen.dart
        posts_provider.dart       # swrly와 병렬로 두는 형태
      bloc/
        posts_screen.dart
        posts_repository.dart     # bloc는 유지, repo에서 swrly 사용
      hooks/                      # 정본 useSwrlyQuery/useSwrlyMutation 스니펫 (라이브러리 미포함)
```

각 폴더는:

- **README.md** — "이 패턴에서 swrly가 담당하는 것 / 라이브러리가 담당하는 것"
- 동일한 화면 (posts 리스트 → 상세)을 각 패턴으로 구현 → 사용자가 비교 가능
- 스킬은 이 파일을 **참조 자료**로 삼아 유사한 코드를 생성

이걸 만들어두면 스킬 프롬프트는 짧아진다: "riverpod 리팩토링은 `example/lib/patterns/riverpod`의 형태를 목표로 잡는다"로 끝.

---

## 5. 스킬 전반의 공통 원칙 (프롬프트에 명시)

정본은 [`doc/CONVENTIONS.md`](CONVENTIONS.md). 아래는 요약이다 — 스킬은
자기 `SKILL.md` 안에서 이 규칙을 반복하지 말고 CONVENTIONS.md를 참조한다:

1. **파괴적으로 다시 쓰지 않는다.** diff는 파일 단위, 사용자 승인 후 적용.
2. **경계 명확화**: swrly = 서버 상태. 클라이언트 상태(폼, 로컬 UI 토글)는 기존 도구 유지.
3. **버전 언급 금지**: README/스킬 모두 버전 리터럴 안 씀 (`docs_freshness_test.dart` 규칙과 일치).
4. **`queryKey` 컨벤션**:
   - 리스트: `['<resource>']` — 예: `['posts']`
   - 상세: `['<resource>', id]` — 예: `['post', 3]`
   - 파라미터: `QueryFamily` + `argKey` 사용 강제 (커스텀 객체 그대로 넣지 않음)
5. **`Query` 정의 배치**: `lib/queries/` 또는 도메인별 `lib/features/<x>/queries/`. 인라인 정의는 위젯 파일 안에서 금지.
6. **`staleTime` 명시 강제**: 스킬이 만드는 모든 쿼리는 `staleTime`을 명시 (기본 0 은 사고 유발).
7. **미지원 기능 안내**: 스킬이 hook / persistence / cancellation을 요청받으면 로드맵 링크와 함께 명시적으로 거절.
8. **테스트 언급**: 스킬이 생성한 쿼리는 최소한 "어떻게 테스트하는지" 한 줄이라도 남긴다 (본 라이브러리의 `readme_snippets_test.dart` 정신).

---

## 6. 배포 형태 — 어떻게 사용자에게 도달하는가

세 가지 옵션, 결정 필요:

| 옵션 | 방식 | 장점 | 단점 |
|---|---|---|---|
| A. **라이브러리 리포에 동봉** | `swrly` 리포의 `.claude/skills/` | 단일 소스, 버전 동기화 자동 | 사용자가 라이브러리 소스를 자기 프로젝트에 clone해야 스킬 접근 가능 |
| B. **별도 리포 `swrly_skills`** | 사용자가 skill install 별도로 | 자기 프로젝트에 clone 없이 사용 가능 | 두 리포 버전 관리 부담 |
| C. **양쪽 다 + install 스크립트** | 라이브러리에 원본, install 스크립트로 사용자 `.claude/`로 복사 | 사용자 경험 최적 | 초기 셋업 복잡 |

**추천 초안**: A로 시작 → 사용자 유입 확인 후 C로 진화. (`opensource-workspace` 사설 리포에 install 스크립트 두는 것도 옵션)

---

## 7. 우선순위 및 단계

### Phase 0 — 준비 (스킬 작성 전)
- [ ] `example/lib/patterns/` 재구성: 최소 `plain`, `provider`, `riverpod`, `bloc` 네 패턴에 대해 동일한 posts 화면 구현
- [ ] 각 패턴 폴더에 README (섹션 4)
- [ ] 스킬에서 참조할 "공통 규칙" 문서 (섹션 5) 를 `doc/CONVENTIONS.md`로 분리

### Phase 1 — 저위험 스킬
- [ ] `swrly-init` (신규/기존 프로젝트 도입)
- [ ] `swrly-refactor` FutureBuilder → QueryBuilder 서브 스킬
- [ ] `swrly-add-query`, `swrly-add-mutation` 템플릿 스킬

### Phase 2 — 상태관리 리팩토링
- [ ] `swrly-refactor-provider`
- [ ] `swrly-refactor-riverpod`
- [ ] `swrly-refactor-bloc`
- [ ] `swrly-refactor-stateful` (setState 패턴 → swrly)

### Phase 3 — 스파게티 & 감사
- [ ] `swrly-refactor-spaghetti` (지도 우선, 점진 이관)
- [ ] `swrly-audit` (안티 패턴 리포트)

### Phase 4 — 배포 경험
- [ ] install 스크립트 or `opensource-workspace` 연동
- [ ] 각 스킬의 실제 실행 로그를 `doc/skills/` 하위에 케이스 스터디로 축적

---

## 8. 결정 필요 사항 (Open Questions)

작업 시작 전 확정하고 싶은 것들:

1. **스킬 배포 형태** — A / B / C 중 어느 것으로 시작?
2. **`example/` 재구성 범위** — 기존 `main.dart`를 `patterns/plain/`으로 이동해도 되는지 (외부 참조 있으면 리다이렉트 필요)
3. **`AsyncValue` 브릿지 (Riverpod/Bloc, v0.5 예정)** 랜딩 순서 — 스킬 이전에 랜딩하면 리팩토링 스킬이 더 깔끔해짐. 순서 조정 여부.
4. **스킬이 만드는 파일 위치 컨벤션** — `lib/queries/` vs `lib/features/<x>/queries/` 중 스킬 기본값 선택.
5. **다국어** — SKILL.md와 사용자 대화 언어를 영어로 통일할지, 한국어 프로젝트면 한국어로 응답할지.

---

## 9. 참고: 스킬 파일 뼈대 (미리보기)

실제 구현 시 각 스킬은 아래 형태:

```
.claude/skills/swrly-init/
  SKILL.md              # 트리거, 인자, 절차, 공통 원칙 링크
  templates/
    query_definition.dart.tmpl
    main_bootstrap.dart.tmpl
  references/
    conventions.md      # doc/CONVENTIONS.md 심볼릭 or 카피
```

`SKILL.md`는 매우 짧게 (~50줄), 결정 트리와 참조만. 상세 규칙은 `doc/`에.

---

_이 문서는 방향성 스케치다. 각 Phase 시작 시 세부 스펙은 별도 이슈/PR로._
