"""Exercise the shipped log filter's classification and redaction, without macOS logs."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/check-apple-services.sh"
FILTER = SOURCE.read_text().split("# BEGIN ACCOUNT ERROR FILTER\n", 1)[1].split(
    "# END ACCOUNT ERROR FILTER", 1
)[0]


class AccountDiagnosticsTests(unittest.TestCase):
    def run_filter(self, text):
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "account-errors.awk"
            script.write_text(FILTER)
            result = subprocess.run(
                [shutil.which("awk") or "awk", "-f", str(script)],
                input=text, text=True, capture_output=True, check=True,
            )
        self.assertEqual(result.stderr, "")
        return set(result.stdout.splitlines())

    def test_nested_errors_and_repeated_events(self):
        text = (
            'akd: Error Domain=AKAuthenticationError Code=-7003 '
            'UserInfo={email=private@example.test password=SECRET MFA=654321 '
            'NSUnderlyingError=Error Domain=NSURLErrorDomain Code=-1202}\n'
            'akd: Error Domain=AKAuthenticationError Code=-7003 token=TOPSECRET\n'
            'commerce: AMSErrorDomain:301 MID=PRIVATE-ID\n'
            'mobileactivationd: com.apple.MobileActivation.ErrorDomain:-4 secret=PRIVATE\n'
        )
        self.assertEqual(self.run_filter(text), {
            "account_error=AKAuthenticationError code=-7003 count=2",
            "account_error=NSURLErrorDomain code=-1202 count=1",
            "account_error=AMSErrorDomain code=301 count=1",
            "account_error=com.apple.MobileActivation.ErrorDomain code=-4 count=1",
        })

    def test_domain_prefixes_and_unknown_domains_cannot_leak(self):
        text = (
            'Error Domain=AKAuthenticationErrorDomain Code=-1 email=private@example.test\n'
            'Error Domain=private@example.test Code=123456\n'
            'prefixAKAuthenticationError Code=-2\n'
            'x.AKAuthenticationError Code=-3\n'
            'AKAuthenticationError Code=1234@example.test\n'
            'AKAuthenticationError Code=-7003Token\n'
            'AKAuthenticationError Code=12345678901234567890\n'
            'AKAuthenticationError Code=1234.56\n'
        )
        self.assertEqual(self.run_filter(text), {
            "account_error=AKAuthenticationErrorDomain code=-1 count=1",
        })

    def test_no_errors_is_explicitly_not_a_success_result(self):
        self.assertEqual(self.run_filter("email=PRIVATE token=SECRET MFA=654321\n"), {
            "account_error_pairs=none_detected",
        })

    def test_packaged_resource_matches(self):
        resource = ROOT / "ios/Henge/Resources/check-apple-services.sh"
        self.assertEqual(SOURCE.read_text(), resource.read_text())


if __name__ == "__main__":
    unittest.main()
