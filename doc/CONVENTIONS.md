# swrly Conventions

이 문서는 `swrly`를 프로젝트에 도입/사용할 때 지켜야 할 컨벤션을 모아둔
정본이다. `.claude/skills/*` 스킬들이 이 규칙을 참조해 코드를 생성한다.
사람도 이 문서만 보면 충분히 일관된 코드를 쓸 수 있어야 한다.

---

## 1. 파괴적 재작성 금지

스킬이 만드는 diff는 파일 단위로 사용자에게 보여주고, 승인 후에만 적용한다.
전면 재작성 · 대량 diff · 리팩토링 폭포는 금지. 스파게티 코드 정리도
"화면 하나씩" 단위로 나눠 진행한다.

**왜**: 서버 상태 캐시 하나를 도입하는 게 앱 재작성 프로젝트가 되면
사용자가 롤백을 못 하고, `swrly` 자체가 '위험한 도구'로 인식된다.

---

## 2. 서버 상태 / 클라이언트 상태 경계

`swrly`는 **서버 상태**만 담당한다. 폼 입력, 로컬 UI 토글, 네비게이션,
편집 중 임시 값 같은 **클라이언트 상태**는 기존 도구(setState / Provider /
Riverpod / Bloc)를 유지한다.

**정의**:

- **서버 상태**: 서버가 원본이고, 우리는 사본을 캐시한다. 다른 곳에서
  바뀔 수 있고, stale이라는 개념이 있다. — 예: 게시글 리스트, 상세, 유저 프로필
- **클라이언트 상태**: 이 앱/이 화면이 원본이다. stale이라는 개념 자체가 없다.
  — 예: 검색어 입력, 다크모드, 선택된 탭, 폼 밸리데이션 상태

**스킬은 이 경계를 흐리는 코드를 생성하지 않는다.** 예를 들어
`ChangeNotifier` 안에 `List<Post>` 필드가 있다면 그건 `swrly`로 이관하지만,
같은 클래스 안의 `bool _isDarkMode` 는 건드리지 않는다.

---

## 3. 버전 리터럴 금지

문서 · 스킬 프롬프트 · 예제 어디에도 `0.3.0` 같은 버전 리터럴을 쓰지 않는다.
버전은 pub 뱃지 하나만 표시한다. `docs_freshness_test.dart`가 이 규칙 위반을
잡아낸다.

**왜**: 릴리스마다 문서를 뒤져 숫자를 바꾸는 것은 실패한다 — 반드시 빠뜨린다.

---

## 4. `queryKey` 컨벤션

키는 캐시 엔트리의 주소다. 오타는 컴파일 에러가 아니라 **silent cache miss**로
이어진다. 이를 피하려면:

- **리스트**: `['<resource>']` — 예: `['posts']`, `['users']`
- **상세**: `['<resource>', id]` — 예: `['post', 3]`
- **파라미터화된 리스트**: `['<resource>', {'page': 2, 'q': 'flutter'}]`
- **문자열 하드코딩 금지**: 항상 `Query` / `QueryFamily`로 감싼다 (다음 항목)

## 5. `Query` / `QueryFamily` 정의는 한 곳에

`(key, fn)` 조합을 인라인으로 반복하지 않는다. 오타 · 시그니처 표류 · 캡처된
클로저의 정체성 문제(README 참고)를 한 방에 막는다.

**배치**:

- 소규모 프로젝트: `lib/queries/` 아래 리소스별 파일
- 중대형 프로젝트: `lib/features/<feature>/queries/` — feature 폴더에 병치
- **인라인 정의 금지**: 위젯 파일 안에서 `Query(key: ['posts'], fn: ...)` 를 만들지 않는다.
  위젯은 이미 정의된 `postsQuery`를 **참조**만 한다.

**예시** (`lib/queries/posts.dart`):

```dart
final postsQuery = Query<List<Post>>(
  key: const ['posts'],
  fn: () => api.getPosts(),
  staleTime: const Duration(seconds: 30),
);

final postQuery = QueryFamily<Post, int>(
  prefix: const ['post'],
  fn: (id) => api.getPost(id),
  staleTime: const Duration(minutes: 1),
);
```

위젯에서:

```dart
QueryBuilder.of(postsQuery, builder: ...);
QueryBuilder.of(postQuery(3), builder: ...);
```

## 6. `staleTime` 명시 강제

스킬이 만드는 모든 쿼리는 `staleTime`을 명시한다. 기본값 0은 "매 리빌드마다
백그라운드 리페치"라 사용자가 의도 없이 그 상태에 놓이면 안 된다.

**권장 초기값** (변경 가능):

- 자주 바뀌지만 조용해도 되는 데이터: `Duration(seconds: 30)`
- 상세 화면처럼 방금 본 걸 다시 안 부를 것: `Duration(minutes: 1)` ~ `Duration(minutes: 5)`
- 거의 안 바뀌는 참조 데이터: `Duration(hours: 1)` 이상

## 7. `QueryFamily`의 `argKey` — 커스텀 객체 금지

`QueryFamily`의 인자가 primitive(int, String)이 아니면 반드시 `argKey`로
primitive 배열로 매핑한다. `toString()` fallback에 기대는 순간 캐시가 새거나
공유되지 않는다.

```dart
// ❌ 나쁨
QueryFamily<Post, PostQuery>(prefix: ['post'], fn: (q) => api.get(q));

// ✅ 좋음
QueryFamily<PostPage, (int, String)>(
  prefix: const ['posts'],
  argKey: (a) => [a.$1, a.$2],
  fn: (a) => api.getPosts(page: a.$1, q: a.$2),
);
```

## 8. Mutation은 rollback closure 를 반환하는 `onMutate` 를 쓴다

Optimistic write을 할 거면 `onMutate`가 rollback closure를 리턴하게 해서
실패 시 자동으로 되돌아가게 한다. `onError`에서 손으로 되돌리는 방식은
edge case에서 새기 쉽다.

```dart
MutationBuilder<Post, String>(
  mutationFn: createPost,
  onMutate: (title) {
    final prev = QueryClient.instance.getQueryData<List<Post>>(['posts']) ?? [];
    QueryClient.instance.setQueryData<List<Post>>(
        ['posts'], [Post.draft(title), ...prev]);
    return () => QueryClient.instance
        .setQueryData<List<Post>>(['posts'], prev);   // 자동 rollback
  },
  onSettled: (_) => QueryClient.instance.invalidateQueries(['posts']),
  builder: ...,
)
```

## 9. Invalidation — 정확도 우선

- 특정 리스트만 무효화하고 싶으면 `postsQuery.invalidate()` (exact).
- 리소스 전체를 무효화해야 하면 `postQuery.invalidateAll()` (family) 또는
  `client.invalidateQueries(['post'])` (prefix).
- **넓게 던지지 않는다**: `client.invalidateQueries([])` 같은 전방위 무효화는
  캐시의 존재 이유를 부정한다. 스킬이 이걸 만들면 안 된다.

## 10. hook 사용자 — `swrly_hooks` 컴패니언 패키지

`swrly` core는 `flutter_hooks`를 의존하지 않는다. 대신 **`swrly_hooks`
컴패니언 패키지**가 별도로 배포되어 hook 사용자에게 검증된 구현을
제공한다 (`flutter_bloc` / `hooks_riverpod` 관례와 동일).

```bash
flutter pub add swrly swrly_hooks
```

```dart
import 'package:swrly_hooks/swrly_hooks.dart';

class PostsPage extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final state = useSwrlyQuery(postsQuery);
    // ...
  }
}
```

컴패니언 패키지가 처리하는 미묘한 것들 (검증 없는 hand-rolled 스니펫이
반복해서 놓치는 부분):

- **Subscriber 라이프사이클**: `onSubscribe`/`onUnsubscribe`로 실제 구독자
  등록 — 그래야 `invalidate()`가 refetch를 트리거하고 `cacheTime` GC가
  위젯이 살아있는 동안 캐시를 지우지 않는다.
- **캐논 key 해시**: `QueryKeyHash.of(key)` 사용 — `List.toString`은
  `['a, b']`와 `['a', 'b']`를 둘 다 `[a, b]`로 직렬화해서 충돌한다.
- **Unhandled async**: `query.fetch()` Future는 `.ignore()` — 리트라이 최종
  실패가 UI엔 `state.error`로 잘 뜨지만 dart zone error handler로
  튀는 것을 막는다.

hook 안 쓰는 사용자는 `swrly_hooks`를 설치하지 않는다 → 부담 없음.
`MutationBuilder`가 필요한 optimistic + rollback 시나리오는 여전히 core
API로 처리; `useSwrlyMutation`은 fire-and-forget 케이스용 얇은 훅이다.

`swrly-init` / `swrly-refactor-hooks` 스킬은 프로젝트에서 `flutter_hooks`를
감지하면 `flutter pub add swrly_hooks`를 실행해 이 패키지를 심는다.

## 11. 테스트 흔적을 남긴다

스킬이 새 쿼리 · mutation을 만들면 최소 한 줄이라도 어떻게 테스트하는지
주석이나 별도 파일로 남긴다. `swrly` 본체가 `readme_snippets_test.dart`로
문서 예제를 검증하는 것과 같은 정신 — "예제는 실행 가능해야 한다".

## 12. 미지원 기능 감지 시 명시적 거절

스킬이 다음 기능을 요청받으면 절대 흉내내지 않고, 로드맵 링크와 함께
"현재 미지원"이라고 응답한다:

- 오프라인/디스크 persistence (`hive`/`shared_preferences` 붙이는 시늉)
- 요청 취소 (v0.4 예정)
- 무한 스크롤 헬퍼 (v0.4 예정)
- 자체 DevTools

**왜**: 사용자가 "swrly가 이걸 지원한다"고 잘못 학습하면 그게 그대로
버그 리포트가 된다.

---

## 부록: 스킬 · 사람이 공통으로 참고하는 체크리스트

새 쿼리 하나를 추가할 때 이 체크리스트를 통과해야 한다:

- [ ] `queryKey`가 문자열 하드코딩이 아니고 `Query`/`QueryFamily`로 감싸져 있다
- [ ] `staleTime`이 명시돼 있다
- [ ] 정의 파일 위치가 §5 컨벤션을 따른다
- [ ] 커스텀 객체를 키에 넣지 않았다 (`argKey` 사용)
- [ ] 위젯 안에서 인라인으로 `Query(...)`를 만들지 않았다
- [ ] 실제 서버 상태다 (클라이언트 상태를 서버 캐시에 얹지 않았다)
