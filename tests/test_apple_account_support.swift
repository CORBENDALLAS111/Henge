import Foundation

@main struct AppleAccountSupportTests {
    static func main() {
        for build in ["22G120", "24G90", "25G83", "26B123"] {
            precondition(AppleAccountSupport.supports(build: build))
        }
        for build in ["23G93", "24G95", "24G90-extra", "", "26B124"] {
            precondition(!AppleAccountSupport.supports(build: build), "unmeasured builds must not become supported")
        }
        precondition(AppleAccountSupport.recommendedBuild == "24G90")
        precondition(AppleAccountSupport.status(identityPresent: false, nativeStatus: 2) == "Not enabled for this Mac")
        precondition(AppleAccountSupport.status(identityPresent: true, nativeStatus: 2) == "Compatibility active")
        precondition(AppleAccountSupport.status(identityPresent: true, nativeStatus: -1) == "Compatibility could not start")
        precondition(AppleAccountSupport.status(identityPresent: true, nativeStatus: nil) == "Identity profile saved")
        precondition(AppleAccountSupport.status(identityPresent: true, nativeStatus: 99) == "Compatibility status unavailable")
        for state in [-1,0,1,2,99] as [Int32] {
            precondition(!AppleAccountSupport.status(identityPresent: true, nativeStatus: state).lowercased().contains("signed in"))
        }
        print("PASS: exact account restore profiles, recommendation and compatibility/authentication status distinction")
    }
}
