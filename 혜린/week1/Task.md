
> 비동기적인 실행 작업 단위, Concurrency를 사용하는데 있어서 기본 단위

```swift
@frozen public struct Task<Success, Failure> : Sendable 
    where Success : Sendable, Failure : Error {
}

```

```swift
Task(priority: TaskPriority?, operation: sending () async -> Success)
Task(priority: TaskPriority?, operation: sending () async throws -> Success)

```

-   구조체로 만들어짐
    
-   작업 클로저를  **생성하자마자, 작업 즉시 실행**
    
-   Task를 변수에 담으면  **취소**(task.cancel()) 처리 가능(이런식으로 필요한 경우에 변수에 담아서 사용)
    
-   Task에 전달되는 클로저의  `리턴값`은 Success, Failure 중 하나
    
    ```swift
    await task.value > 작업의 성공의 결과값에 접근 (return 값(Sendable 채택해야함))
    await task.result > 작업의 결과를 Result 타입으로 반환
    
    ```
-   Task끼리는 병렬적으로 일 실행됨 → 순서 보장되지 않음 내부의 작업들은 순서 보장, 비동기적으로 동작하는 것을 가능하게 만듦(async 동작)
    
-   상위 Task의 메타데이터를 상속함 (우선 순위, 실행 액터, 로컬변수(Task-local))(취소는 상속되지 않음)
-   우선순위 지정 가능, 우선 처리하고 싶은 일을 처리 가능
-   self 캡처할 필요없음, 암시적으로 알아서 캡처, 해제 다 되기 때문에…
    -   Task.detached 생성할 때는 self 반드시 붙여야함. 독립적인 작업을 만드는 것이기 때문에…기존의 메타데이터를 상속받지 않음
    
-   Task handle이 할당 해제 되어도 비동기 작업이 자동으로 취소되지 않고 백그라운드에서 계속 실행됩니다.
    
-   Task.yield → 기회만 양보, 다른 Task가 완료될때까지 기다리지 않음, 스케줄러의 판단에 따라 다시 실행 기회를 받을 수 있음

# Q&A

**Task는 왜 구조체로 만들어졌을까?**

1.  Task는 비동기 작업의 실행과 생명주기를 관리하는 중요한 역할을 함 참조 타입으로 구현될 경우 여러 곳에서 동일한 Task 객체를 참조하고 수정할 가능성이 있음
2.  Task는 한 번 생성되면 그 상태가 변경되지 않아야한다.
3.  값데이터는 복사되기 때문에 data race가 발생할 위험이 없음. 다른 스레드에 task 전달 가능

**리턴값이 Sendable을 채택해야하는 이유는?**

1.  Sendable이란  `동시성 환경에서 안전하게 전달될 수 있는 타입`을 의미하는 프로토콜
    
2.  첫번째 이유는 동시성의 안전성, 동시성 환경에서 데이터의 안전한 공유를 보장하기 위해
    
    1.  Task는 멈춰졌다가 다른 스레드에서 다시 실행될 수 있잖아요?
        
    2.  리턴값이 메인 스레드나 다른 스레드로 전달될 때 Data race가 발생하지 않아야함
        
        여러 스레드에서 동시에 접근할 때 발생할 수 있는 버그를 컴파일 타임에 방지함
        
3.  Sendable 타입의 특징
    
    1.  값 타입은 기본적으로 Sendable을 만족함
    2.  클래스는 @unchecked Sendable 혹은 final class이면서 모든 프로퍼티가 Sendable을 만족해야함
    3.  Array, Dictionary 등의 컬렉션은 요소가 Sendable을 만족하면 Sendable임

```swift
// ✅ 값 타입은 자동으로 Sendable
struct User: Sendable {
    let name: String
    let age: Int
}

// ✅ final class + Sendable 프로퍼티
final class ImmutablePerson: Sendable {
    let id: UUID
    let name: String
    
    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

// ❌ mutable 상태를 가진 클래스는 Sendable 불가
class MutablePerson {
    var name: String
    
    init(name: String) {
        self.name = name
    }
}

// Sendable을 만족하는 타입을 리턴하는 Task
func fetchUser() async -> User {
    let user = User(name: "Kim", age: 25)
    return user
}

// ❌ Sendable을 만족하지 않는 타입을 리턴하면 컴파일 에러
func fetchPerson() async -> MutablePerson {
    return MutablePerson(name: "Kim")
}

```

**Task.yield 메서드 언제 실질적으로 사용하는지?**

-   긴 반복 작업에서의 양보
    
    ```swift
    func processLargeData() async {
        let items = Array(1...1000000)
        
        for (index, item) in items.enumerated() {
            // 매 1000개 아이템마다 다른 Task에게 기회를 줌
            if index % 1000 == 0 {
                await Task.yield()
            }
            
            // 무거운 처리 작업
            process(item)
        }
    }
    
    // 실제 사용 예시
    Task {
        // 우선순위가 높은 작업
        await processLargeData()
    }
    
    Task {
        // 다른 중요한 작업도 중간중간 실행 기회를 얻을 수 있음
        await doOtherImportantWork()
    }
    
    ```
    
-   UI 업데이트와 함께 사용
    
-   게임이나 애니메이션 로직에서의 활용
    
    ```swift
    class GameEngine {
        func updateGameState() async {
            while isGameRunning {
                // 게임 상태 업데이트
                updatePositions()
                checkCollisions()
                
                // 프레임마다 다른 작업에게 기회를 줌
                await Task.yield()
                
                // 프레임 시간 조절
                try? await Task.sleep(for: .milliseconds(16)) // 약 60fps
            }
        }
    }
    
    // 게임 실행
    Task {
        // 게임 로직
        await gameEngine.updateGameState()
    }
    
    Task {
        // 동시에 실행되어야 하는 사운드 처리
        await soundEngine.process()
    }
    
    ```
    
    Task.yield()를 사용할 때 주의할 점:
    
    -   과도한 사용 주의
        -   너무 자주 yield를 호출하면 오히려 성능이 저하될 수 있습니다
        -   적절한 간격으로 사용하는 것이 중요합니다
    -   실행 보장 없음
        -   yield()는 다른 작업에게 실행 기회를 주는 것이지, 반드시 실행된다는 보장은 없습니다
        -   시스템의 스케줄링에 따라 다시 바로 현재 작업이 실행될 수도 있습니다
    -   비용 고려
        -   yield() 자체도 작은 오버헤드가 있으므로, 정말 필요한 곳에서만 사용해야 합니다

# 예시

> UI ↔ 백그라운드 작업 사이의 브릿지 역할(비동기 작업 환경을 만들어주는 역할)

```swift
class ProfileViewController: UIViewController {
    private let loader: UserLoader

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        Task {
            do {
                let user = try await loader.loadUser(withID: userID)
                userDidLoad(user)
            } catch {
                handleError(error)
            }
        }
    }
}

```

> 중복되는 Task 생성 방지

```swift
class ProfileViewController: UIViewController {
    private let userID: User.ID
    private let loader: UserLoader
    private var user: User?
    private var loadingTask: Task<Void, Never>?
    ...

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        **guard loadingTask == nil** else {
            return
        }

        loadingTask = Task {
            do {
                let user = try await loader.loadUser(withID: userID)
                userDidLoad(user)
            } catch {
                handleError(error)
            }

            loadingTask = nil
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        **loadingTask?.cancel()
        loadingTask = nil**
    }

    ...
}

```

> detached

```swift
class ProfileViewController: UIViewController {
    ...

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard loadingTask == nil else {
            return
        }

        loadingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            do {
                let user = try self.database.loadModel(withID: self.userID)
                await self.userDidLoad(user)
            } catch {
                await self.handleError(error)
            }

            await self.loadingTaskDidFinish()
        }
    }

    ...

    private func loadingTaskDidFinish() {
        loadingTask = nil
    }
}

```

일반적으로 독립적인 실행 컨텍스트를 사용하는 **최상위 작업을 명시적으로 생성하려는 경우 detached Task만 사용하는것이 좋습니다.**
