# Swift Concurrency 1주차

## Task

```Swift
@frozen public struct Task<Success, Failure> : Sendable where Success : Sendable, Failure : Error {
}

extension Task where Success == Never, Failure == Never {
    @available(*, deprecated, message: "Task.Priority has been removed; use TaskPriority")
    public typealias Priority = TaskPriority

    @available(*, deprecated, message: "Task.Handle has been removed; use Task")
    public typealias Handle = Task

    @available(*, deprecated, message: "Task.CancellationError has been removed; use CancellationError")
    public static func CancellationError() -> CancellationError

    @available(*, deprecated, renamed: "yield()")
    public static func suspend() async
}

extension Task where Failure == any Error
``` 

### Never란?
- 완전한 종료를 보장: Never는 값이 절대 반환되지 않음을 나타낸다. 즉, 함수가 정상적으로 종료되지 않거나, 항상 예외를 던지거나, 프로그램이 종료된다는 것을 의미한다. 이를 통해 컴파일러는 이 함수가 호출된 후에 어떤 코드가 실행될 수 없는지를 이해하게된다.
- 제네릭 타입의 안전성 향상: 제네릭 타입에서 Never를 사용하면 특정 조건을 만족하지 않는 경우에 대한 타입 안전성을 제공한다. 예를 들어, 제네릭 함수에서 특정 타입이 Never를 반환하는 경우, 그 타입을 사용하는 로직은 실행될 수 없음을 보장한다.
- 패턴 매칭과 오류 처리: Never는 패턴 매칭을 사용할 때, 모든 경우의 수를 처리하지 않아도 되는 경우에 유용하다. 예를 들어, switch 문에서 모든 가능한 경우를 다루었음을 나타내기 위해 Never를 사용하면, 컴파일러가 모든 경우가 처리되었다고 판단하게 할 수 있다.
- 타입 시스템의 표현력 향상: Never는 특정 상황에서 불가능한 동작을 명시적으로 표현할 수 있게 해준다. 이는 코드의 가독성을 높이고, 의도한 동작을 명확히 하여 유지보수에 용이하다.

``` Swift
@frozen public enum Never
``` 

- 정상적으로 리턴하지 않는 함수의 리턴 타입 Ex.) fatalError의 리턴 타입이 Never다.

``` Swift
public func fatalError(_ message: @autoclosure () -> String = String(), file: StaticString = #file, line: UInt = #line) -> Never
``` 

- Generic 클래스에서 작업할 때 유용하다
    - 예를 들어, Result 타입은 Value가 "항상" error임을 나타내거나, Error에서 error가 절대 발생하지 않는것을 나타내기 위해 "Never"를 사용합니다.
    
``` Swift
func fatalErrorFunction() -> Never {
    fatalError("This function never returns")
}

func process<T>(value: T) -> T {
    if value is Int {
        return value // 정상적인 경우
    } else {
        fatalErrorFunction() // 이 경우는 절대 실행되지 않음
    }
}
``` 

### Task의 Never를 Error 타입으로 했을 때

```Swift
enum ImageError: Error {
    case failedToLoad
}

extension ImageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .failedToLoad:
            return "Failed to load image"
        }
    }
}

func someTask() -> Task<Void, any Error> {
    return Task<Void, any Error> {
        throw ImageError.failedToLoad
    }
}

func test() async throws {
    try await someTask().value
}

Task {
    do {
        try await test()
    } catch {
        print(error.localizedDescription) // Failed to load image
    }
}
```

### Task에서 self를 명시적으로 캡쳐하지 않아도되는 이유
- Task의 경우 전달된 클로저가 즉시 실행되며 클로저의 실행이 종료되면 바로 릴리즈된다. 이 때문에 self를 캡쳐해도 메모리 누수의 위험이 적으며 그렇게 때문에 self.의 명시적인 사용을 요구하지 않는다.
- @_implicitSelfCapture 라는 어트리뷰트가 있어서 self를 생략 가능하도록 할 수 있다.

```Swift
@discardableResult
@_alwaysEmitIntoClient
public init(
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: __owned @Sendable @escaping () async -> Success
)
```
