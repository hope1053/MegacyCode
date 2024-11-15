# Never 타입 변수에 할당
> 불가능!

Swift에서 Never 타입은 함수나 클로저의 반환 타입으로만 사용되며, 변수나 상수에 직접 할당할 수 없습니다.
- Closures, methods, computed properties, and subscripts can also be nonreturning.
- There’s no way to create an instance of Never
```swift
let favoriteNumber: Result<Int, Never> = .success(42)
switch favoriteNumber {
case .success(let value):
    print("My favorite number is", value)
}
```
위의 코드에서 failureType이 Never로 선언돼있는데 이건 Result가 항상 성공할 것 이라는 뜻을 내포하고 있음. 그래서 switch문에서도 .failure 케이스에 대해 코드를 작성해주지 않아도 오류가 뜨지 않음.
```swift
func fatalError(
    _ message: @autoclosure () -> String = String(),
    file: StaticString = #file,
    line: UInt = #line
) -> Never
```
fatalError의 타입로 Never..흠
- Never의 특징 중 하나, 제어권을 호출 위치로 리턴하지않는다. ?