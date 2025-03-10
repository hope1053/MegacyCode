# How to cancel Task

Task는 Cooperative Cancellation(협력적 취소)를 사용한다.

작업을 중지하라고 지시할 수는 있지만, 취소 요청을 받더라도 즉시 강제 종료되지 않는다.

개발자가 명시적으로 취소 상태를 확인하는 코드를 작성해야 한다.

- **`Task.checkCancellation()`**을 호출하여 CancellationError를 발생
- **`Task.isCancelled`** Bool 값을 확인하여 직접 처리 가능

```swift
// 아래 두 코드는 동일
// 1
try Task.checkedCancellation()

// 2
guard !Task.isCancelled else {
		throw CancellationError()
}
```

### 작업 취소시 알아야 할 사항

1. `Task.cancel()` 메서드를 호출해서 작업을 명시적으로 취소
    1. Task.isCancelled = true로 설정 
    2. 모든 작업은 Task.isCancelled 를 확인하여 작업이 취소 되었는지 여부를 확인 가능
2. `Task.checkCancellation()` 호출 후 취소되거나 아무 작업도 수행되지 않는 경우 CancellationError 발생
    1. isCancelled 확인 후에 취소라면 에러 던짐
3. `Task.sleep()` 사용해서 일정 시간 지날 때까지 대기하는 경우 취소하면 자동으로 종료되고  CancellationError 발생
4. SwiftUI의 `.task()` 수정자를 사용하여 작업을 시작한 경우 해당 작업은 뷰가 사라질 때 자동으로 취소
    1. 뷰(view)와 수명이 일치하기 때문에, 뷰가 사라지면 자동으로 작업을 취소시킴 → 리소스 관리 효율화

## Example

아래 예시는 Task 사용해서 URL에서 일부 데이터 가져오고, 배열 디코딩해서 평균 반환하는 함수

```swift
func getAverageTemperature() async {
    let fetchTask = Task {
        let url = URL(string: "https://hws.dev/readings.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let readings = try JSONDecoder().decode([Double].self, from: data)
        let sum = readings.reduce(0, +)
        return sum / Double(readings.count)
    }

    do {
        let result = try await fetchTask.value
        print("Average temperature: \(result)")
    } catch {
        print("Failed to get data.")
    }
}

await getAverageTemperature()
```

명시적인 취소는 없지만, `URLSession.shared.data(from:)` 호출이 계속하기 전에 작업이 여전히 활성 상태인지 확인하기 때문에 암시적인 취소 존재.
작업 취소되면 `data(from:)` 자동으로 URLError 발생시키고 나머지 작업은 실행되지 않음.

### `URLSession`의 암시적 취소 체크의 동작 방식

**네트워크 요청 과정**

```swift
// 1. 요청 시작
let (data, _) = try await URLSession.shared.data(from: url)
// 2. 네트워크 통신 중
// 3. 응답 수신
```

이 과정에서 data(from:) 메서드는 내부적으로 다음과 같은 작업을 수행

1. 요청을 보내기 전에 Task의 취소 상태를 확인
2. 데이터를 받는 도중에도 주기적으로 Task의 취소 상태를 확인
3. 취소되었다면 URLError를 발생시킴

**실제 예시 이해하기**

```swift
let fetchTask = Task {
    // 만약 이 시점에서 Task가 취소되었다면
    let (data, _) = try await URLSession.shared.data(from: url) 
    // ⬆️ data(from:)이 자동으로 취소를 감지하고 에러를 발생시킴
    
    // 이후 코드는 실행되지 않음
    let readings = try JSONDecoder().decode([Double].self, from: data)
    ...
}
```

이것은 마치 다음과 같은 검사를 내부적으로 수행하는 것과 같습니다

```swift
// URLSession이 내부적으로 수행하는 것과 유사한 로직
if Task.isCancelled {
    throw URLError(.cancelled)
}
```

따라서 개발자가 명시적으로 취소 상태를 확인하는 코드를 작성하지 않아도, URLSession이 자동으로 이를 처리해주는 것이다.

### **취소 체크의 타이밍 문제**

그러나 암시적 확인은 네트워크 **호출 전에** 발생하므로 실제로는 실제 취소 지점이 될 가능성이 없다. (*아래 순서 참고)
대부분의 사용자는 모바일 네트워크 연결을 사용하기 때문에 특히 사용자의 연결 상태가 좋지 않은 경우 네트워크 호출에 이 작업의 대부분의 시간이 걸릴 가능성이 높습니다.

**네트워크 요청의 실제 흐름**

```swift
let (data, _) = try await URLSession.shared.data(from: url)
```

이 한 줄의 코드는 실제로 다음과 같은 순서로 실행됩니다:

1. 취소 상태 확인 (매우 빠름)
2. 네트워크 요청 시작
3. 데이터 다운로드 (오래 걸림)
4. 응답 수신

**실제 문제점**

네트워크 요청의 대부분의 시간은 실제 데이터를 다운로드하는 과정에서 소요된다.

- 모바일 네트워크는 불안정할 수 있음
- 연결 속도가 느릴 수 있음
- 데이터 크기가 클 수 있음

따라서 초기의 취소 확인만으로는 실제 데이터를 다운로드하는 긴 시간 동안의 취소를 효과적으로 처리할 수 없습니다.

**권장되는 해결책**

```swift
func getAverageTemperature() async {
    let fetchTask = Task {
        let url = URL(string: "https://hws.dev/readings.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        try Task.checkCancellation() // ✅ 네트워크 요청 후 추가 확인 ✅
        let readings = try JSONDecoder().decode([Double].self, from: data)
        let sum = readings.reduce(0, +)
        return sum / Double(readings.count)
    }

    do {
        let result = try await fetchTask.value
        print("Average temperature: \(result)")
    } catch {
        print("Failed to get data.")
    }
}

await getAverageTemperature()
```

이렇게 긴 작업 후에 추가로 취소 상태를 확인하는 것이 더 효과적이며, 네트워크 요청 후 취소를 명시적으로 확인하도록 작업 체크할 수 있다.

 한 번만 호출하면 작업이 더 이상 필요하지 않은 데이터를 계산하는 데 시간을 낭비하지 않는지 확인할 수 있다.

**취소 직접 처리** 

일부 리소스를 정리하거나 다른 계산을 수행해야 하는 경우 같이 취소를 직접 처리하는 경우, 
Task.checkCancellation() 대신 `Task.isCancelled` 값을 확인해야 한다.

```swift
func getAverageTemperature() async {
    let fetchTask = Task {
        let url = URL(string: "https://hws.dev/readings.json")!

        do {
            let (data, _) = try await URLSession.shared.data(from: url) // ⭐ 암시적 취소 지점
            if Task.isCancelled { return 0.0 } // ✅ 명시적 취소 지점

            let readings = try JSONDecoder().decode([Double].self, from: data)
            let sum = readings.reduce(0, +)
            return sum / Double(readings.count)
        } catch {
            return 0.0 // ⭐ 암시적 취소 지점에서 취소되면 catch로 이동
        }
    }

    fetchTask.cancel()

    let result = await fetchTask.value
    print("Average temperature: \(result)")
}

await getAverageTemperature()
```

암시적 취소나 명시적 취소 둘 중 하나가 트리거 되면 작업은 오류를 발생시키지 않고 0을 반환한다.

**암시적 취소 지점 (data(from:))**

`let (data, _) = try await URLSession.shared.data(from: url)`

- 이 부분에서 취소되면 **`URLError`**를 throw 합니다
- 이 에러는 외부 **`do-catch`** 블록에서 잡히고 **`return 0.0`**이 실행된다.

**명시적 취소 지점 (Task.isCancelled)**

`if Task.isCancelled { return 0.0 }`

- 여기서는 직접 취소 상태를 확인하고 0을 반환합니다
- 에러를 발생시키지 않고 직접 값을 반환합니다

따라서 두 지점 모두 결과적으로는 0을 반환하지만, 그 과정이 다릅니다:

- 암시적 취소: URLError 발생 → catch 블록 → 0 반환
- 명시적 취소: 조건문으로 직접 확인 → 0 반환

이렇게 설계된 이유는 취소된 경우에도 일관된 기본값(0)을 반환하여 에러 처리를 단순화하기 위함

동기, 비동기 함수 모두에서 `Task.checkCancellation()` 및 `Task.isCancelled` 모두 사용할 수 있다. 

비동기 함수는 동기 함수를 자유롭게 호출할 수 있으므로 취소 확인은 불필요한 작업을 방지하는 것만큼 중요하다.

---
[원문 자료](https://www.hackingwithswift.com/quick-start/concurrency/how-to-cancel-a-task)
