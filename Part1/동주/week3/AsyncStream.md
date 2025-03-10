
1. 

```swift
Task {
    /// 하위 구조화(동시) 작업을 만들어서 다 각자 일을 시키고
    
    async let image1 = fetchImage(num: 1)  // 결과값이 아직 안 생겼지만 기다리지 않음
    async let image2 = fetchImage(num: 2)
    async let image3 = fetchImage(num: 3)
    async let image4 = fetchImage(num: 4)
    
    
    /// 실제 기다리는 중단 포인트
    let fetch1 = try await image1
    let fetch2 = try await image2
    let fetch3 = try await image3
    let fetch4 = try await image4
}

```

- async let은 구조적 동시성을 따른다.
- async let으로 선언된 작업은 동일한 범위(Task) 내에서 관리되며, Task가 종료될 때 작업도 자동으로 취소됩니다.
- 각각의 비동기 작업을 명시적으로 정의한다.
- try await을 통해 각 작업의 결과를 개별적으로 기다린다. → 작업마다 다른 에러 처리 로직을 추가할 수 있다.

장점

- 코드가 직관적이다.
- 작업 중 특정 Task가 실패하더라도 다른 Task의 결과를 계속 기다릴 수 있다.
- async let으로 선언된 작업은 취소 가능하므로 메모리와 리소스를 더 효율적으로 관리할 수 있다.

단점

- 결과를 하나씩 기다리는 과정에서 코드가 길어질 수 있다.
- 작업 결과를 병렬로 처리하고 싶다면 별도의 코드 작성이 필요하다.

1. 

```swift
let (fetchImage1, fetchImage2, fetchImage3, fetchImage4) = await (try? image1, try image2, try image3, try image3)
```

- 모든 비동기 작업의 결과를 한 번에 기다리고 병합한다.
- 튜플 형태로 작업 결과를 반환받아 한 번에 처리할 수 있다.

장점

- 코드가 짧고 간결하다.
- 모든 작업의 결과를 한 번에 기다려 병합할 수 있어 직관적이다.
- 간단한 오류 처리(try?)를 병렬 작업에 적용하기 적합하다.

단점

- 각 작업에 대한 개별적인 오류 처리 로직을 작성하기 어렵다.
- 작업간 의존성이 높은 경우 가독성이 떨어질 수 있다.

> 두 코드의 성능 차이는 없다.
> 

---

## AsyncSequence

```swift
protocol AsyncSequence<Element, Failure>
```

AsyncSequence란 Swift에서 비동기 데이터 스트림을 순차적으로 처리할 수 있도록 설계된 `프로토콜`이다. Sequence와 유사하게 데이터를 순차적으로 반복할 수 있고 추가로 **비동기 작업을 지원하기 위해 데이터를 비동기적으로 생성하고 소비한다.**

- 일부 데이터는 즉시 사용할 수 있지만, 나머지는 준비될 때까지 `await`를 사용해 기다려야 할 수 있다

```swift
for await value in AsyncSequence { }
for try await value in AsyncSequence { }
```

eg) URLSession.shard.bytes(from: )

```swift
let url = URL(string: "https://example.com")!
let (data, _) = try await URLSession.shared.bytes(from: url)

for try await byte in data {
    print(byte)
} 
```

- byte(from:) 메서드는 비동기 바이트 스트림을 제공하는 AsyncSequence이다.

### 특징

`AsyncSequence`는 데이터를 직접 생성하거나 보유하지 않는다. 

대신, Sequence와 마찬가지로 데이터를 어떻게 반복해서 접근할 것인지를 정의한다.

데이터를 직접 생성하거나 저장하지 않기 때문에, 데이터를 어떻게 생성하고 반복할지는 `makeAsyncIterator()` 메서드를 통해 정의된다.

실제 데이터는 `makeAsyncIterator()`가 반환하는 `AsyncIterator` 객체에 의해 생성된다.

### 데이터 생성 방법

AsyncSequence는 데이터를 비동기적으로 생성하기 위해 `AsyncIteratorProtocol`을 사용

```swift
protocol AsyncIteratorProtocol {
    associatedtype Element
    mutating func next() async throws -> Element?
}
```

`AsyncIteratorProtocol` = 반복자

AsyncSequence의 makeAsyncIterator() 메서드가 반환하는 타입이 Protocol 준수

`AsyncIteratorProtocol`은 데이터를 한 번에 하나씩 비동기적으로 생성하고 반환한다.

데이터를 소비하는 쪽에서는 반복자의 `next()` 메서드를 호출하며 다음 데이터를 비동기적으로 요청한다.

### **데이터 생성 과정**

1. AsyncSequence는 makeAsyncIterator()를 호출해 반복자(`AsyncIteratorProtocol`)를 생성한다.
2. 반복자는 next() 메서드를 통해 데이터를 하나씩 반환한다.
3. 데이터가 준비되지 않았을 경우, await로 데이터가 준비될 때까지 대기한다.
4. 반복자가 nil을 반환하면 반복이 종료된다.

eg) 1부터 howHigh까지 숫자를 생성하는 비동기 시퀀스

```swift
struct Counter: AsyncSequence {
    typealias Element = Int
    let howHigh: Int

    struct AsyncIterator: AsyncIteratorProtocol {
        let howHigh: Int
        var current = 1

        mutating func next() async -> Int? {
            guard current <= howHigh else {
                return nil
            }

            let result = current
            current += 1
            return result
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(howHigh: howHigh)
    }
}

```

- AsyncSequence 정의
    - Element는 Int로 정의
- AsyncIteratorProtocol
    - AsyncIterator는 AsyncSequence의 반복자로, 숫자를 생성하고 반환한다.
    - next() 메서드로 숫자를 하나씩 반환한다.

```swift
for await number in Counter(howHigh: 10) {
    print(number, terminator: " ")
}
// Prints "1 2 3 4 5 6 7 8 9 10 "

let stream = Counter(howHigh: 10)
    .map { $0 % 2 == 0 ? "Even" : "Odd" }
for await s in stream {
    print(s, terminator: " ")
}
// Prints "Odd Even Odd Even Odd Even Odd Even Odd Even "
```

<aside>
❗

AsyncSequence가 데이터를 직접 생성하지 않고 데이터를 생성하는 방법을 정의한다.
AsyncSequence를 “요리사”, AsyncIterator를 “요리 도구”로 생각하자.
AsyncIterator가 호출될 때마다 요리가 하나씩 완성되어 손님(호출자)에게 제공된다.

반대) 데이터를 미리 보유한 경우

```swift
let numbers = [1, 2, 3, 4, 5] // 데이터가 이미 준비되어 있음
for number in numbers {
    print(number)
}
```

</aside>

## AsyncStream

```swift
struct AsyncStream<Element>
```

`AsyncStream`는 Swift에서 `AsyncSquence` 프로토콜을 구현한 구조체이다. 

이를 통해 비동기적으로 데이터를 생성하고 제공하는 스트림을 만들 수 있다. 

특히 AsyncStream은 Callback 기반 또는 Delegate 기반의 기존 API를 async/await으로 통합하는 데 적합하다.

> `AsyncSequence`를 생성하는 인터페이스
> 

```swift
// #1 기본 스트림 생성
let stream = AsyncStream<Int> { continuation in
    for i in 1...10 {
        continuation.yield(i) // 데이터를 스트림에 추가
    }
    continuation.finish() // 스트림 종료
}

// #2 비동기 데이터 생성
let stream = AsyncStream<Int> { continuation in
    Task.detached {
        for i in 1...5 {
            await Task.sleep(1_000_000_000) // 1초 대기
            continuation.yield(i)
        }
        continuation.finish()
    }
}

Task {
    for await value in stream {
        print("Received: \(value)")
    }
    print("Stream finished.")
}
```

eg)

**기존의 call back 기반 코드**

```swift
class QuakeMonitor {
    var quakeHandler: ((Quake) -> Void)?

    func startMonitoring() {
        // 감지 시작
    }

    func stopMonitoring() {
        // 감지 중단
    }
}
```

call back 방식으로 구현된 quakeHandler를 AsyncStream으로 변환해 async-await 기반으로 처리할 수 있도록 해보자.

**AsyncStream 생성**

```swift
extension QuakeMonitor {
    static var quakes: AsyncStream<Quake> {
        AsyncStream { continuation in
            let monitor = QuakeMonitor()

            // 데이터를 스트림에 추가
            monitor.quakeHandler = { quake in
                continuation.yield(quake)
            }

            // 스트림 종료 시 호출되는 작업
            continuation.onTermination = { @Sendable _ in
                monitor.stopMonitoring()
            }

            // 모니터링 시작
            monitor.startMonitoring()
        }
    }
}
```

- yield를 통해 스트림에 Quake(Element)를 제공
- `AsyncStream.Continuation` 객체를 사용해 데이터를 스트림에 추가하거나 종료한다.
    - `AsyncStream.Continuation`은 데이터를 추가(yield)하거나 종료(finish)하는 역할을 한다.
    

비동기 적으로 호출

```swift
Task {
    for await quake in QuakeMonitor.quakes {
        print("Quake detected at: \(quake.date)")
    }
    print("Stream finished.")
}
```

## TaskGroup + AsyncStream

```swift
func images(for urls: [URL]) -> AsyncStream<(URL, NSImage)> 
{
    AsyncStream { continuation in
        let task = Task {
            await withTaskGroup(of: (URL, NSImage).self) { group in
                for url in urls {
                    group.addTask { await (url, self.downloadImage(url: url)) }
                }

                for await tuple in group {
                    continuation.yield(tuple)
                }

                continuation.finish()
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
```

- `TaskGroup`으로 병렬 작업 실행
    - 각 URL에 대해 `downloadImage(url:)` 작업을 비동기로 추가
- AsyncStream을 반환해 다운로드된 결과를 실시간으로 전달
    - 이미지를 다운로드할 때마다 continuation.yield()을 호출해 스트림에 전달
