# Concurrency

## 1. Continuation

### Continuation

Swift에서 비동기 흐름을 제어하고, 콜백 기반의 비동기 작업을 async-await 방식으로 변환하기 위한 개념적 용어. `CheckedContinuation`과 `UnsafeContinuation` 두 구조체가 있다.

### **struct CheckedContinuation**

개발 중 비동기 작업의 `resume` 호출을 한 번만 정확히 실행하는지 검사하는 구조체이다.

런타임에서 `resume` 호출 규칙을 준수하는지 확인해 비동기 코드의 안정성을 향상시킨다.

### struct **UnsafeContinuation**

`CheckedContinuation`과 같은 기능을 제공하지만, 런타임에서 `resume` 규칙 검사 없이 동작한다. 안정성이 확인된 코드에서 퍼포먼스를 향상시키기 위해 사용한다.

### withCheckedContinuation**(isolation:function:_:) &** withCheckedThrowingContinuation**(isolation:function:_:)**

```swift
@backDeployed(before: macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0)
func withCheckedContinuation<T>(
    isolation: isolated (any Actor)? = #isolation,
    function: String = #function,
    _ body: (CheckedContinuation<T, Never>) -> Void
) async -> sending T
```

withCheckedContinuation(isolation:function:_:): CheckedContinuation을 사용하여 특정 actor 격리 상태에서 안전하게 비동기 작업을 수행한다. 

`resume`이 누락되거나 중복으로 호출되면 런타임에서 검사하여 경고를 출력하며, 격리 상태(isolation)를 사용해 **동시성 안전성**을 보장할 수 있다. 

isolation 파라미터로 특정 actor를 지정하여 해당 actor의 격리 상태에서 작업이 수행되도록 보장할 수도 있다.

withCheckedThrowingContinuation(isolation:function:_:): 오류를 발생시킬 가능성이 있는 비동기 작업을 CheckedContinuation을 사용해 안전하게 수행한다. 작업 중 오류가 발생하면 resume(throwing:)으로 오류를 전달할 수 있으며, 격리 상태가 설정된 actor 내에서 안전하게 실행된다.

## 2. Actor

### Data Race

Data Race는 여러 Task 또는 Thread가 동시에 같은 메모리 위치에 접근해 쓰기 작업을 수행하면 발생하는 문제다. 

### Class에서의 Data Race

참조 타입인 클래스는 동일한 인스턴스를 여러 Task가 공유할 수 있다.

```swift
class BankAccount {
    var balance: Int = 0
    
    func deposit(amount: Int) {
        balance += amount
    }
    
    func withdraw(amount: Int) {
        balance -= amount
    }
}

let account = BankAccount()

Task {
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<10 {
            group.addTask {
                account.deposit(amount: 10)  // 동시에 접근
            }
            group.addTask {
                account.withdraw(amount: 10) // 동시에 접근
            }
        }
    }
    print("Final balance:", account.balance)
}
```

동시에 여러 Task에서 account에 접근하면서 data race가 발생한다.

이유는 Class가 `shared mutable state`이기 때문이다. (공유된 변경 상태)

- Shared(공유된): 어러 Task나 Thread가 동일한 메모리 위치에 접근할 수 있는 상태
- Mutable(변경 가능한): 상태를 읽는 것뿐만 아니라 수정할 수 있는 경우

### Struct에서의 Data Race

구조체는 값 타입이라 Task 간에 독립적으로 전달되므로 shared mutable state 자체가 사라진다. 하지만 구조체도 참조를 공유하는 상황에 문제가 발생할 수 있다.

```swift
struct BankAccount {
    var balance: Int = 0

    mutating func deposit(amount: Int) {
        balance += amount
    }

    mutating func withdraw(amount: Int) {
        balance -= amount
    }
}

var account = BankAccount() // `account`는 값 타입이지만, 여기서 공유될 가능성 존재

Task {
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<10 {
            group.addTask { account.deposit(amount: 10) }  // 에러 발생 가능
            group.addTask { account.withdraw(amount: 10) } // 에러 발생 가능
        }
    }
    print(account.balance) // 상태가 꼬일 가능성
}
```

값 타입인데 왜 data dace가 발생할 수 있을까

1. Main Actor Isolation
- account는 Main Actor에 의해 격리된 상태로 간주된다.
- Task 클로저 내부는 비동기적으로 실행되며 메인 액터와는 다른 컨텍스트에서 동작한다.

1. 값 타입이지만 참조 공유 가능
- Task 클로저에서 account를 캡처하면, 값을 복사하지 않고 참조를 공유하려고 시도할 수 있다.

---

### Data Race 해결: Actor

동시성 안전성을 제공하는 참조 타입. 클래스와 비슷하지만, 내부적으로 직렬 수행 큐(Serial Execution Queue)를 사용해 데이터를 안전하게 보호한다.

- Actor-isolated State
    - Actor 내부의 상태는 Actor 외부에서 직접 접근할 수 없다.
    - 외부에서 상태에 접근하려면 비동기 메서드(await)를 통해 접근해야 한다.
- Serial Execution Queue
    - Actor 내부에서의 작업은 한 번에 하나의 Task만 실행되도록 보장한다.
    - 내부적으로 직렬 실행 큐를 사용한다.
- Thread-agnostic
    - actor는 특정 스레드에 종속되지 않는다.
    - 여러 스레드에서 actor를 호출해도, 내부는 항상 직렬화되어 안전하게 처리된다.

```swift
actor BankAccount {
    var balance: Int = 0
    
    func deposit(amount: Int) {
        print("deposit: \(amount)")
        balance += amount
    }
    
    func withdraw(amount: Int) {
        print("withdraw: \(amount)")
        balance -= amount
    }
}

let account = BankAccount()

Task {
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<10 {
            group.addTask {
                await account.deposit(amount: 20)  // 안전하게 순차적으로 접근
            }
            group.addTask {
                await account.withdraw(amount: 10) // 안전하게 순차적으로 접근
            }
        }
    }
    let finalBalance = await account.balance
    print("Final balance:", finalBalance)
}

```

→ 여러 Task가 동시에 BankAccount에 접근하려고 해도, 한 번에 하나의 Task만 실행된다.

### Actor isolation

## 3. DispatchQueue.main vs Main.actor

Main.actor는 actor의 특수한 형태로, 모든 작업이 Main Thread에서 실행되도록 보장한다. 

### DispatchQueue.main와 Main.actor의 차이점

- 사용 방식
    - **MainActor**
        1. async/await와 통합되어 동작한다.
        2. 비동기 작업에 적합하며, await 키워드를 통해 자연스럽게 동기화 작업을 작성할 수 있다.
        3. 컴파일러가 MainActor 격리를 강제한다.
        
        ```swift
        @MainActor
        func updateUI() {
            print("This is running on the Main Actor")
        }
        
        Task {
            await updateUI() // MainActor를 통해 메인 스레드에서 실행
        }
        
        DispatchQueue.main.async {
            print("This is running on the Main DispatchQueue")
        }
        ```
        
    - **DispatchQueue.main**
        1. GCD의 일부로 동작하며, 큐에 작업을 제출하는 방식으로 사용된다.
        2. async/await와 직접적인 통합은 없다.

- 스레드 제어
    - **MainActor**
        1. 컴파일러가 런타임에서 작업이 반드시 메인 스레드에서 실행되는 것을 검증할 수 있다.
        2. 특정 함수, 클래스, 변수를 메인 스레드에 격리할 수 있다.
        
        ```swift
        @MainActor
        class ViewModel {
            var value: Int = 0
        
            func updateValue() {
                value += 1 // 항상 메인 스레드에서 실행됨
            }
        }
        ```
        
    - **DispatchQueue.main**
        1. 스레드 격리가 컴파일러에 의해 자동으로 적용되지 않는다.
        
        ```swift
        class ViewModel {
            var value: Int = 0
        
            func updateValue() {
                DispatchQueue.main.async {
                    self.value += 1 // 직접적으로 명시해야 함
                }
            }
        }
        ```
        
- Async/Await와 통합
    - **MainActor**
        
        ```swift
        @MainActor
        func fetchAndDisplayData() async {
            let data = await fetchData() // 비동기 작업
            updateUI(with: data) // 메인 스레드에서 실행
        }
        ```
        
    - **DispatchQueue.main**
        
        ```swift
        func fetchAndDisplayData() {
            Task {
                let data = await fetchData() // 비동기 작업
                DispatchQueue.main.async {
                    self.updateUI(with: data) // 메인 스레드에서 실행
                }
            }
        }
        ```
        

- 컴파일러 검증
    - **MainActor**
        - MainActor로 격리된 상태에 비동기 호출 없이 접근하려고 하면 컴파일 에러가 발생한다.
    - **DispatchQueue.main**
        - 스레드 안전성이나 메인 스레드에서 실행 여부를 검증하지 않는다. 개발자가 직접 해야 한다.
