#!/usr/bin/env python3

import base64
import hashlib
import json
import os
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path


STATE_DIRECTORY = Path.home() / ".local" / "state" / "dms-ntfy-center"
VERIFICATION_KEYWORDS = re.compile(
    r"验证码|校验码|动态码|动态密码|一次性(?:密码|口令)|短信码|认证码|确认码|"
    r"安全码|登录码|登录代码|验证代码|安全代码|授权码|激活码|"
    r"verification\s*code|security\s*code|authentication\s*code|"
    r"confirmation\s*code|login\s*code|one[-\s]?time(?:\s+(?:password|code))?|"
    r"passcode|\bOTP\b|\b2FA\b|\bMFA\b|\bPIN\b",
    re.IGNORECASE,
)
VERIFICATION_CANDIDATES = re.compile(
    r"(?<![A-Z0-9])(?:[A-Z0-9]{4,8}|[0-9]{3}[- ][0-9]{3})(?![A-Z0-9])",
    re.IGNORECASE,
)


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def normalize_verification_text(text):
    normalized = []
    for character in str(text or ""):
        codepoint = ord(character)
        if 0xFF10 <= codepoint <= 0xFF19:
            normalized.append(chr(codepoint - 0xFF10 + ord("0")))
        elif 0xFF21 <= codepoint <= 0xFF3A:
            normalized.append(chr(codepoint - 0xFF21 + ord("A")))
        elif 0xFF41 <= codepoint <= 0xFF5A:
            normalized.append(chr(codepoint - 0xFF41 + ord("a")))
        else:
            normalized.append(character)
    return "".join(normalized)


def span_distance(left, right):
    if left[1] < right[0]:
        return right[0] - left[1]
    if right[1] < left[0]:
        return left[0] - right[1]
    return 0


def extract_verification_code(text):
    normalized = normalize_verification_text(text)
    keyword_spans = [match.span() for match in VERIFICATION_KEYWORDS.finditer(normalized)]
    if not keyword_spans:
        return ""
    candidates = []
    for match in VERIFICATION_CANDIDATES.finditer(normalized):
        value = re.sub(r"[- ]", "", match.group(0)).upper()
        if not any(character.isdigit() for character in value):
            continue
        distance = min(
            span_distance(match.span(), keyword_span) for keyword_span in keyword_spans
        )
        if distance <= 80:
            candidates.append((distance, match.start(), value))
    if not candidates:
        return ""
    candidates.sort()
    return candidates[0][2]


def annotate_message(event):
    message = dict(event)
    searchable_text = f"{message.get('title', '')}\n{message.get('message', '')}"
    message["verification_code"] = extract_verification_code(searchable_text)
    return message


def read_payload():
    raw = sys.stdin.readline()
    if not raw:
        raise RuntimeError("No configuration was provided")
    payload = json.loads(raw)
    server = str(payload.get("serverUrl", "")).strip().rstrip("/")
    topic = str(payload.get("topic", "")).strip()
    if not server:
        raise RuntimeError("Server URL is required")
    if not topic:
        raise RuntimeError("Topic is required")
    if not server.startswith(("http://", "https://")):
        raise RuntimeError("Server URL must start with http:// or https://")
    payload["serverUrl"] = server
    payload["topic"] = topic
    return payload


def authentication_header(config):
    token = str(config.get("accessToken", "")).strip()
    if token:
        return f"Bearer {token}"
    username = str(config.get("username", "")).strip()
    password = str(config.get("password", ""))
    if not username:
        return ""
    credentials = base64.b64encode(f"{username}:{password}".encode()).decode()
    return f"Basic {credentials}"


def make_request(config, url, data=None):
    headers = {"User-Agent": "dms-ntfy-center/1.1"}
    authorization = authentication_header(config)
    if authorization:
        headers["Authorization"] = authorization
    if data is not None:
        headers["Content-Type"] = "application/json; charset=utf-8"
    return urllib.request.Request(url, data=data, headers=headers)


def ssl_context(config):
    if config.get("verifyTls", True):
        return None
    return ssl._create_unverified_context()


def topic_url(config, query):
    encoded_topic = urllib.parse.quote(config["topic"], safe="")
    encoded_query = urllib.parse.urlencode(query)
    return f"{config['serverUrl']}/{encoded_topic}/json?{encoded_query}"


def state_path(config):
    identity = f"{config['serverUrl']}\n{config['topic']}".encode()
    digest = hashlib.sha256(identity).hexdigest()[:24]
    return STATE_DIRECTORY / f"{digest}.last_id"


def read_last_id(config):
    try:
        return state_path(config).read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def write_last_id(config, message_id):
    if not message_id:
        return
    path = state_path(config)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(message_id, encoding="utf-8")
    os.replace(temporary, path)


def watch(config):
    delay = 1
    while True:
        since = read_last_id(config) or "10s"
        try:
            request = make_request(config, topic_url(config, {"since": since}))
            with urllib.request.urlopen(
                request, timeout=90, context=ssl_context(config)
            ) as response:
                emit({"kind": "status", "state": "online"})
                delay = 1
                for raw_line in response:
                    event = json.loads(raw_line.decode("utf-8"))
                    if event.get("event") != "message":
                        continue
                    emit({"kind": "message", "data": annotate_message(event)})
                    write_last_id(config, event.get("id", ""))
        except KeyboardInterrupt:
            return
        except Exception as error:
            emit({"kind": "status", "state": "offline", "error": str(error)})
            time.sleep(delay)
            delay = min(delay * 2, 30)


def history(config):
    hours = max(1, min(int(config.get("historyHours", 24)), 168))
    limit = max(5, min(int(config.get("historyLimit", 20)), 50))
    request = make_request(
        config, topic_url(config, {"poll": "1", "since": f"{hours}h"})
    )
    messages = []
    with urllib.request.urlopen(
        request, timeout=20, context=ssl_context(config)
    ) as response:
        for raw_line in response:
            event = json.loads(raw_line.decode("utf-8"))
            if event.get("event") == "message":
                messages.append(annotate_message(event))
    messages.sort(key=lambda item: item.get("time", 0), reverse=True)
    emit({"kind": "history", "data": messages[:limit]})


def publish(config):
    message = str(config.get("message", "")).strip()
    title = str(config.get("title", "")).strip() or "Custom message"
    if not message:
        raise RuntimeError("Message cannot be empty")
    body = json.dumps(
        {
            "topic": config["topic"],
            "title": title,
            "message": message,
            "tags": ["speech_balloon"],
        },
        ensure_ascii=False,
    ).encode()
    request = make_request(config, f"{config['serverUrl']}/", body)
    with urllib.request.urlopen(
        request, timeout=20, context=ssl_context(config)
    ) as response:
        result = json.loads(response.read().decode("utf-8"))
    emit({"kind": "published", "data": result})


def main():
    try:
        command = sys.argv[1] if len(sys.argv) > 1 else ""
        config = read_payload()
        if command == "watch":
            watch(config)
        elif command == "history":
            history(config)
        elif command == "publish":
            publish(config)
        else:
            raise RuntimeError("Usage: ntfy_client.py watch|history|publish")
    except Exception as error:
        emit({"kind": "error", "error": str(error)})
        raise SystemExit(1)


if __name__ == "__main__":
    main()
