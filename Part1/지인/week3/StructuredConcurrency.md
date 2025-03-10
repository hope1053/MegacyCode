### 동시적으로 보이지만 순차적인 코드

- 단순 반복문 내부 코드의 async 동시 처리가 되지 않음. 순차적으로 동작됨
- 정확히는 await 될 때 멈췄다 다시 실행될 때 어떤 쓰레드에서도 실행될 수 있음

```swift
func fetchImages(urlArray: [String]) async -> [UIImage] {
    var imageArray: [UIImage] = []
      
    for url in urlArray {
        if let image = await fetchImage(urlString: url) {
            imageArray.append(image)
        }
    }
    
    return imageArray
}
```

- Task 내부에서 순차적으로 동작, 직렬적으로

```swift

Task {
    let image1 = try await fetchImage(num: 1)
    let image2 = try await fetchImage(num: 2)
    let image3 = try await fetchImage(num: 3)
    let image4 = try await fetchImage(num: 4)
}
```

# Structured Concurrency 특징

**작업 계층 구조**

- 부모-자식 관계의 계층 구조로 작업이 조직
- 부모 작업은 모든 자식 작업이 완료될 때까지 완료되지 않음 (⭐ 무조건 보장!)
- 자식 작업에서 더 높은 우선순위 설정되면 부모 우선순위도 자동으로 높아짐
- 자식 작업은 부모 작업의 메타데이터(우선순위, 로컬 변수 등)을 상속

**자동 리소스 관리**

- 작업이 완료되거나 취소될 때 리소스가 자동으로 정리
- 그래서 메모리 누수와 같은 리소스 관리 문제의 위험 감소

**향상된 오류 처리**

- 자식 작업에서 발생한 오류를 부모 작업에서 처리 가능
- 오류 전파 메커니즘이 내장

**취소 및 우선순위 관리**

- 작업 취소와 우선순위 관리를 위한 메커니즘을 제공
- 협력적 취소(Cooperative Cancellation) 개념을 지원

**가독성과 유지보수성 향상 (async-let)**

- async/await 구문을 사용하여 비동기 코드를 동기 코드와 유사하게 작성
- 코드의 흐름을 더 쉽게 이해하고 관리

**Task와 TaskGroup 지원** 

- 개별 작업을 위한 Task와 여러 작업을 관리하기 위한 TaskGroup을 제공
- 병렬 실행을 쉽게 구현

# Structured Concurrency 형태

## 1) async let (동시 바인딩, 암시적 하위작업 생성)

**[ 동작 방식 ]**

1. `async-let`으로 선언된 상수는 비동기 작업에 대한 **참조를 생성**
   - 작업 완료를 기다리지 않고 다음 코드 바로 진행
2. 선언 즉시 해당 작업이 시작되며, 다음 코드 라인으로 즉시 진행
3. 실제로 결과값이 필요한 시점에서 await 키워드 사용해 작업 완료를 기다림

**[ 비차단 실행 ]**

`async-let` 으로 된 작업이 시작되면 작업 완료를 기다리지 않고 즉시 다음 코드라인으로 진행

ex) 백그라운드에서 실행되는 것과 유사하며 메인 프로그램 흐름은 중단되지 않고 계속 진행

**[ 지연된 결과 접근 ]**

`async-let`으로 선언된 상수는 실제 결과값을 갖는 것이 아닌 미래 완료될 작업에 대한 참조를 나타냄

이 참조는 `await` 키워드를 통해 실제 결과 값으로 변환됨

ex) 택배 추적 번호와 비슷, 번호(참조)는 있지만 실제 물건(결과)는 나중에 도착

**실행 예제 코드**
```swift
Task {
    /// 하위 구조화(동시) 작업을 만들어서 다 각자 일을 시키고
    async let image1 = fetchImage(num: 1)  // 결과값이 아닌 참조를 갖고 있음
    async let image2 = fetchImage(num: 2)
    async let image3 = fetchImage(num: 3)
    async let image4 = fetchImage(num: 4)
    
    
    /// 실제 기다리는 중단 포인트
    let fetch1 = try await image1 // 새로운 값이 생성되는 시점
    let fetch2 = try await image2
    let fetch3 = try await image3
    let fetch4 = try await image4
    imageArray.append(contentsOf: [fetch1, fetch2, fetch3, fetch4])
    
    // 1) 한번에 하는 방식
    let (fetched1, fetched2, fetched3, fetched4) = try await (image1, image2, image3, image4)
    imageArray.append(contentsOf: [fetched1, fetched2, fetched3, fetched4])
    // 2) await만 한번에 try는 개별적
    let (fetchImage1, fetchImage2, fetchImage3, fetchImage4) = await (try? image1, try image2, try image3, try image3)
    // 3) 개별 try await 방식
    (try await image1, try await image2, try await image3, try await image4)
    // 4) 배열을 사용한 방식
    let images = await [try image1, try image2, try image3, try image4]
                try await [image1, image2, image3, image4]
    imageArray.append(contentsOf: images)
}
```
    

### 1-1) async-let 장단점

**[ 장점 ]**

- 코드가 간결해서 읽기 쉬움
- 고정된 수의 비동기 작업 처리할 때 적합
- 서로 다른 반환 타입의 작업을 쉽게 처리
- 간단한 병렬 작업 수행할 때 쉽게 사용 할 수 있음

**[ 단점 ]**

- 런타임에 동적으로 작업 수 변경 어려워 배열 같은거 받아서 처리하기 어려움
    
    ```swift
    // 고정된 수의 async-let만 사용 가능
    func downloadImages(urls: [URL]) async throws -> [UIImage] {
        guard !urls.isEmpty else { return [] }
        
        async let image1 = downloadImage(from: urls[0])
        async let image2 = urls.count > 1 ? downloadImage(from: urls[1]) : nil
        async let image3 = urls.count > 2 ? downloadImage(from: urls[2]) : nil
        // ... 더 많은 URL에 대해 이런 식으로 계속 작성해야 함
        
        let results = try await [image1, image2, image3].compactMap { $0 }
        return results
    }
    
    // TaskGroup 사용시 URL 배열 크기 상관없이 동적으로 작업 생성 가능
    func downloadImages(urls: [URL]) async throws -> [UIImage] {
        return try await withThrowingTaskGroup(of: UIImage.self) { group in
            for url in urls {
                group.addTask {
                    return try await downloadImage(from: url)
                }
            }
            
            var images: [UIImage] = []
            for try await image in group {
                images.append(image)
            }
            return images
        }
    }
    ```
    
- TaskGroup과 달리 개별 작업을 직접 취소하거나 관리하기 어려움
    
    ```swift
    // task1이나 task2를 개별적으로 취소할 방법이 없습니다.
    async let task1 = someAsyncFunction1()
    async let task2 = someAsyncFunction2()
    
    // group.cancelAll()을 호출하여 모든 작업을 취소하거나
    // 개별 작업에 대한 참조를 유지하여 특정 작업만 취소할 수 있습니다.
    await withTaskGroup(of: SomeType.self) { group in
        group.addTask { await someAsyncFunction1() }
        group.addTask { await someAsyncFunction2() }
    
    }
    ```
    
- TaskGroup과 달리 작업 완료 순서대로 결과 처리하기 어려움
    
    ```swift
    // 작업이 동시에 시작되지만, 결과는 선언된 순서대로 처리됨.
    // fast, medium 작업이 먼저 완료 됐어도 slow 작업이 완료될 때까지 기다려야 한다.
    
    func performTasks() async {
        async let slow = slowTask()
        async let medium = mediumTask()
        async let fast = fastTask()
        
        // 결과는 항상 선언 순서대로 처리됩니다
        let result1 = await slow    // 3초 후 결과
        let result2 = await medium  // 2초 후 결과 (하지만 이미 완료되었음)
        let result3 = await fast    // 1초 후 결과 (하지만 이미 완료되었음)
        
        print(result1, result2, result3)
    }
    ```
    

## 2) TaskGroup

**[ 주요 특징 ]**

- 동적 작업 추가: (async-let과 달리) 런타임에 필요한 만큼 작업을 추가 가능
- 병렬 실행: 추가된 모든 작업은 병렬로 실행
- 결과 수집: 작업이 완료되는 대로 결과를 수집 (async-let은 선언된 순서로 수집)
- 오류 처리: 그룹 내의 작업에서 발생한 오류를 처리
- 취소 관리: 필요시 그룹 내의 모든 작업을 한 번에 취소
- 리소스 관리: 작업이 완료되면 자동으로 리소스 정리
예제 코드
```swift
func downloadImages(from urls: [URL]) async throws -> [UIImage] {
    return try await withThrowingTaskGroup(of: (Int, UIImage).self) { group in
        // 1. 그룹 생성: withThrowingTaskGroup을 사용하여 TaskGroup 생성

        var images:  UIImage?] = Array(repeating: nil, count: urls.count)

        // 2. 작업 추가: 각 URL에 대한 다운로드 작업을 그룹에 추가, 하위 동시작업 실행 (동시)
        for (index, url) in urls.enumerated() {
            group.addTask {  // 작업을 기다리는게 아니라, 바로 다음 반복주기로 이동
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    return (index, image)
                }
                throw DownloadError.invalidImage
            }
        }

        /// 비동기 반목문 ⭐️⭐️⭐️ (순차적) -> 그래서 쓰레드에 대한 문제가 없다.
        /// 병렬(동시)작업에서 리턴이 한개씩 될때마다 리턴을 받아서 실행
        /// (처음부터 group에 모든 데이터가 있는 것이 아니라, 데이터가 생길때마다 실행)
        /// group.waitForAll()  ===> 사용할 필요 없음. for await 반복문이 어차피 다 기다림
        for try await (index, image) in group {
            images[index] = image
        }
        return images.compactMap { $image }

        // 5. 완료 대기: 모든 작업이 끝날 때까지 자동으로 대기

        // 6. 오류 처리: try-catch 블록 내에서 처리 가능
        
        
    }
}

```
    
**Task 생성 메소드 매개변수 분석**
    
  ```swift
  await withTaskGroup(
      of: Sendable.Type(자식 작업들에서 리턴하게 되는 데이터 타입), 
      returning: GroupResult.Type(부모 작업에서 리턴되는 데이터 타입)
    ) { group in // 부모 작업 클로저
      
      group.addTask { // 자식 작업 생성		
      
      }
  }
  ```
    

### 2-1) TaskGroup 장단점

**[ 장점 ]**

- 동적 작업 관리 : 런타임에 동적으로 작업을 추가, 배열이나 컬렉션의 요소에 대해 작업을 수행할 때 특히 유용
- 유연한 결과 처리 : 작업이 완료되는 순서대로 결과를 처리
- 세밀한 제어 : 작업의 취소, 우선순위 설정 등 더 세밀한 제어가 가능
- 에러 처리 : 개별 작업의 에러를 더 유연하게 처리 가능하며, 전체 그룹도 가능
- 확장성 : 대량의 작업을 효율적으로 관리

**[ 단점 ]**

- async-let에 비해 사용 방법이 더 복잡할 수 있음
- 매우 간단한 작업 사용시 TaskGroup 사용하면 __*오버헤드__ 발생할 수 있음 (간단할 땐 async-let으로)
  - 오버헤드는 TaskGroup 생성 및 관리에 따른 추가적인 시스템 리소스 사용
  - 오버헤드는 Task 스케줄링 및 동기화에 필요한 추가 처리 시간
  - 메모리 할당 및 해제에 따른 오버헤드
- 실행 순서가 __*비결정적__ 일 수 있어 버그 재현이 어려울 수 있음
  - 비결정적이란 여러 작업이 동시에 실행되어 각 실행마다 작업의 완료 순서가 다름을 의미
  - 만약 특정 버그가 특정 실행 순서에서만 발생한다면, 그 순서를 정확히 재현하기 어려울 수 있음

### 2-2) TaskGroup 생성 메소드 종류

| **메소드** | **설명** | **에러 처리** | **결과 반환** |
| --- | --- | --- | --- |
| [**withTaskGroup**](https://developer.apple.com/documentation/swift/withtaskgroup(of:returning:isolation:body:))  | 기본적인 TaskGroup 생성. 에러를 던지지 않는 작업에 사용 | 불가능 | 가능 |
| [**withThrowingTaskGroup**](https://developer.apple.com/documentation/swift/withthrowingtaskgroup(of:returning:isolation:body:)) | 에러를 던질 수 있는 작업을 위한 TaskGroup 생성 | 가능 | 가능 |
| [**withDiscardingTaskGroup**](https://developer.apple.com/documentation/swift/withdiscardingtaskgroup(returning:isolation:body:)) | 결과를 무시하는 TaskGroup 생성. 에러를 던지지 않는 작업에 사용 | 불가능 | 불가능 |
| [**withThrowingDiscardingTaskGroup**](https://developer.apple.com/documentation/swift/withthrowingdiscardingtaskgroup(returning:isolation:body:)) | 결과를 무시하고 에러를 던질 수 있는 TaskGroup 생성 | 가능 | 불가능 |


❓ DiscardingTask는 언제 사용하는가?
- 자식 작업이 Void를 리턴할 때, 리턴 데이터 타입이 없을 때
- 메모리 해제를 빠르게 시킬 수 있음
- 자식 작업의 결과 값을 수집할 필요가 없음
```swift
func printSomething() async -> Void {
    print("비동기 작업")
}

func fetchImagesGroupForArray() async -> Void {
    await withDiscardingTaskGroup { group in // 리턴타입이 없을 때 사용, 병렬적으로 동작만 시킴.
        for _ in 1...10 {
            group.addTask {
                await printSomething()
            }
        }
    }
}
```


## **Async-let / TaskGroup**

<img width="1101" alt="image" src="https://github.com/user-attachments/assets/1cf114d3-eca5-4aaa-827d-4c3698062681">


| **특징** | **Async-Let** | **TaskGroup** |
| --- | --- | --- |
| **작업 추가 방식** | 정적 (코드 작성 시 고정) | 동적 (런타임에 추가 가능) |
| **실행 시작 시점** | 선언 즉시 실행 | **`group.addTask`** 호출 시 즉시 실행 |
| **결과 처리 순서** | 선언된 순서대로 대기 | 완료된 순서대로 처리 가능 |
| **사용 사례** | 고정된 수의 독립적인 병렬 작업 | 배열/컬렉션 등 동적인 데이터 구조 병렬 처리 |
| **취소 관리** | 개별 취소 불가능 | **`group.cancelAll()`**으로 전체 취소 가능 |

결론

- **`Async-Let`**: 고정된 수의 독립적인 병렬 작업을 수행할 때 적합
- **`TaskGroup`**: 런타임에 작업 수가 동적으로 변하거나, 완료된 순서대로 결과를 처리해야 할 때 적합

## TaskGroup / Task / Task.detached

| **특성** | **TaskGroup** | **Task (비구조화된 작업)** | **Task.detached** |
| --- | --- | --- | --- |
| 구조적 동시성 | O | X | X |
| 부모-자식 관계 | O | X | X |
| 우선순위 상속 | O | O (생성 컨텍스트에서) | X |
| 작업 로컬 값 상속 | O | O | X |
| 액터 컨텍스트 상속 | O | O | X |
| 자동 취소 전파 | O | X | X |
| 독립성 | 낮음 | 중간 | 높음 |
| 주요 사용 사례 | 동적인 수의 관련 작업 처리 | 단일 비동기 작업, 부분적 독립성 필요 | 완전히 독립적인 작업 |

**[ 구성 방법 ]** 

```swift
// 1. TaskGroup
await withTaskGroup(of: SomeType.self) { group in
    group.addTask { */* 자식 작업 */* }
    group.addTask { */* 다른 자식 작업 */* }
}

// 2. Task
Task {
    // 비구조화된 작업
    ~~self.~~anotherWork (암시적 self 캡쳐, 생략 가능)
}

// 3. Task.detached
Task.detached {
    // 완전히 독립적인 작업
    **self.**anotherWork (명시적 self 캡쳐, 독립적 실행이라 현재 컨텍스트를 캡쳐하지 않으므로 명시적으로 필요)
}
```
