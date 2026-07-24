import importlib.util
import unittest
from pathlib import Path


CLIENT_PATH = Path(__file__).parents[1] / "scripts" / "ntfy_client.py"
SPEC = importlib.util.spec_from_file_location("ntfy_client", CLIENT_PATH)
NTFY_CLIENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NTFY_CLIENT)


class VerificationCodeParserTests(unittest.TestCase):
    def test_chinese_numeric_code(self):
        message = "【夸克】验证码9361，用于登录。"
        self.assertEqual(NTFY_CLIENT.extract_verification_code(message), "9361")

    def test_ignores_unrelated_short_number(self):
        message = "【西安一二三云】03编号验证码790401，有效期5分钟。"
        self.assertEqual(NTFY_CLIENT.extract_verification_code(message), "790401")

    def test_english_alphanumeric_code(self):
        message = "Your verification code is AB12CD."
        self.assertEqual(NTFY_CLIENT.extract_verification_code(message), "AB12CD")

    def test_separated_code(self):
        self.assertEqual(
            NTFY_CLIENT.extract_verification_code("PIN: 123 456"), "123456"
        )

    def test_fullwidth_code(self):
        message = "动态密码：１２３４５６，请勿泄露。"
        self.assertEqual(NTFY_CLIENT.extract_verification_code(message), "123456")

    def test_keyword_in_title(self):
        message = "iPhone 验证码短信\n登录代码为 884422"
        self.assertEqual(NTFY_CLIENT.extract_verification_code(message), "884422")

    def test_rejects_number_without_keyword(self):
        self.assertEqual(
            NTFY_CLIENT.extract_verification_code("订单 123456 已经发货"), ""
        )


if __name__ == "__main__":
    unittest.main()
