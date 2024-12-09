# CancelTaskBag [🔗](http://minsone.github.io/swift-concurrency-AnyCancelTaskBag)
> RxSwift의 disposeBag 아이디어를 차용하여 Task를 담은 객체가 deinit 될 때 Task가 cancel 되도록 구현해보자!
## 문제가 되는 상황
```swift
class Alpha {
    init() {
        print("\(Date()) init")
        Task {
            print("\(Date()) Before Hello Alpha")
            try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            print("\(Date()) After Hello Alpha")
        }
    }
    
    deinit {
        print("\(Date()) deinit")
    }
}
```
이러한 객체가 있고
```swift
func run() {
    _ = Alpha()
}
```
이렇게 실행을 시키면 객체를 변수에 할당하지 않았기 때문에 함수 실행 후 바로 deinit됨
```swift
/** Output
2022-06-19 16:16:36 +0000 init
2022-06-19 16:16:36 +0000 deinit
2022-06-19 16:16:36 +0000 Before Hello Alpha
2022-06-19 16:16:46 +0000 After Hello Alpha
*/
```
하지만! Task 자체가 취소된건 아니기 때문에 10초 후에 print문이 찍히고 있다...
**이런 경우 Task가 제대로 취소되도록 구현해줘야함!**
## 어떻게 해결할 수 있을까?
**Task는 변수에 담을 수 있기 때문에 담아서 객체가 deinit 될 때 취소해주면 될 것 같다.**
근데 매번 Task 생성할 때 마다 변수에 할당하고 deinit 시 취소해주는건 너무 번거롭다 ..
## DisposeBag 아이디어를 활용해보자
RxSwift에서는 DisposeBag이라는 개념을 활용해서 Disposable들을 담아뒀다가 DisposeBag이 deinit 될 때 담긴 Disposable들을 모두 취소해주고 있음.
**그럼 CancelTaskBag을 만들어보자!**
### 1. AnyCancellableTask 선언
```swift
public protocol AnyCancellableTask {
    func cancel()
}

extension Task: AnyCancellableTask {}
```
cancel 메서드가 있는 프로토콜 생성 후 Task가 채택하도록 구현
### 2. AnyCancellableTaskBag 선언
```swift
public final class AnyCancelTaskBag {
    // 내부에 Task들을 들고 있을 배열
    private var tasks: [any AnyCancellableTask] = []
    
    public init() {}

    // 배열에 Task 추가
    public func add(task: any AnyCancellableTask) {
        tasks.append(task)
    }

    // 들고 있는 Task들 모두 취소, 배열 삭제
    public func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
    
    // TaskBag 객체가 deinit 될 때 Task들 모두 취소되게 메서드 실행
    deinit {
        cancel()
    }
}
```
```swift
extension Task {
    public func store(in bag: AnyCancelTaskBag) {
        bag.add(task: self)
    }
}
```
Task 생성 후 .store(in: TaskBag) 실행하여 TaskBag에 Task를 추가 할 수 있도록 메서드 추가
```swift
Observable.just()
    .subscribe()
    .disposed(by: disposeBag)
```
요 느낌적인 느낌
## 써보자!
```swift
class Alpha {
    let bag = AnyCancelTaskBag()
    
    init() {
        print("\(Date()) init")
        Task {
            print("\(Date()) before Hello Alpha")
            try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            print("\(Date()) After Hello Alpha")
        }.store(in: bag)
    }
    
    deinit {
        print("\(Date()) deinit")
    }
}

func run() {
    _ = Alpha()
}
```
이렇게 실행해주면 이제 객체 deinit 이후 Task가 취소돼서 실행되지 않는걸 볼 수 있다~
```swift
/** Output
2022-06-19 16:49:19 +0000 init
2022-06-19 16:49:19 +0000 deinit
2022-06-19 16:49:19 +0000 before Hello Alpha
*/
```

### How to gracefully cancel a task [🔗](https://medium.com/@harryyan1238/how-to-gracefully-cancel-a-task-in-swift-7f901914081a)
> Cooperative cancellation을 깔끔하게 구현해볼 수 있을까?🧐
```swift
func myTask() async {
    // Check for cancellation
    do {
        Task.checkCancellation()
    } catch {
        // Handle cancellation
        cleanupResources()
        return
    }

    // Do some work
    await doSomething()

    // Check for cancellation again
    do {
        Task.checkCancellation()
    } catch {
        // Handle cancellation
        cleanupResources()
        return
    }

    // Do some more work
    await doSomethingElse()
}
```
기존에 cancellation 체크를 해주기 위해서는 중복 코드가 발생하는 경우가 많음.
이렇게 매번 함수 호출 전에 체크를 해주는게 아니라 throwable async 메서드를 선언해서 사용하는 것이 좋음 !
```swift
func updateUserAttribute(_ attribute: UserAttributeEntity, value: String) async throws {
    return try await withCheckedThrowingContinuation { continuation in
        guard Task.isCancelled == false else {
            continuation.resume(throwing: CancellationError())
            return
        }
        
        sdk.setUserAttributeType(attribute.toMEGAUserAttribute(), value: value, delegate: RequestDelegate { result in
            guard Task.isCancelled == false else {
                continuation.resume(throwing: CancellationError())
                return
            }
            continuation.resume(with: result.map{_ in })
        })
    }
}
```
이런 메서드가 있을 때도 completion이 필요한 메서드 호출 전, 후에 한번씩 체크를 해주는 중복 코드가 있는 것을 확인할 수 있음.
```swift
public func withAsyncThrowingValue<T>(in operation: (@escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
    return try await withCheckedThrowingContinuation { continuation in
        guard Task.isCancelled == false else {
            continuation.resume(throwing: CancellationError())
            return
        }

        operation { result in
            guard Task.isCancelled == false else {
                continuation.resume(throwing: CancellationError())
                return
            }

            continuation.resume(with: result)
        }
    }
}
```
이런 util성 메서드를 선언해두면 operation에 필요한 로직을 전달하면 매번 중복되는 cancellation 체크 로직을 작성하지 않고도 취소 여부를 확인할 수 있다~~
```swift
func updateUserAttribute(_ attribute: UserAttributeEntity, value: String) async throws {
    return try await withAsyncThrowingValue(in: { completion in
        sdk.setUserAttributeType(attribute.toMEGAUserAttribute(), value: value, delegate: RequestDelegate { result in
            switch result {
            case .success:
                completion(.success)
            case .failure:
                completion(.failure(GenericErrorEntity()))
            }
        })
    })
}
```
요렇게 ~