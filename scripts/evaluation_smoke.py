"""Read-only HTTP smoke check for automated hackathon evaluators.

The only writes are short-lived login sessions, which are revoked before exit.
No career plan, progress, XP, CQ, reward, or HR state is changed.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


class CheckFailed(RuntimeError):
    pass


def call(base_url, method, path, token=None, payload=None):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(base_url + path, data=body, headers=headers, method=method)
    try:
        with urlopen(request, timeout=30) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else {}
    except HTTPError as error:
        raw = error.read()
        return error.code, json.loads(raw) if raw else {}
    except URLError as error:
        raise CheckFailed(f"server unavailable: {error.reason}") from error


def data(response):
    value = response.get("data", response)
    if not isinstance(value, dict):
        raise CheckFailed("response is not a JSON object")
    return value


def expect(name, status, expected, response, evidence=None):
    if status != expected:
        detail = response.get("error", {}).get("code", "unexpected response")
        raise CheckFailed(f"{name}: expected HTTP {expected}, got {status} ({detail})")
    result = {"check": name, "status": "PASS", "http": status}
    if evidence is not None:
        result["evidence"] = evidence
    print(json.dumps(result, ensure_ascii=False))


def login(base_url, username, password):
    status, response = call(
        base_url,
        "POST",
        "/api/auth/login",
        payload={"username": username, "password": password},
    )
    expect(f"login:{username}", status, 200, response)
    token = response.get("token")
    if not isinstance(token, str) or not token:
        raise CheckFailed(f"login:{username}: token missing")
    return token


def read_check(base_url, token, name, path):
    status, response = call(base_url, "GET", path, token)
    expect(name, status, 200, response)
    return data(response)


def logout(base_url, token):
    status, response = call(base_url, "POST", "/api/auth/logout", token)
    expect("session-revoked", status, 200, response)


def main():
    parser = argparse.ArgumentParser(
        description="Verify Career Quest through public, employee, HR, and optional AI contracts."
    )
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8000",
        help="Running Career Quest origin (default: %(default)s)",
    )
    parser.add_argument(
        "--with-openai",
        action="store_true",
        help="Also request an explanation and plan draft; may call the configured provider.",
    )
    args = parser.parse_args()
    base_url = args.base_url.rstrip("/")
    employee_password = os.getenv("EVALUATION_EMPLOYEE_PASSWORD", "Employee123!")
    hr_password = os.getenv("EVALUATION_HR_PASSWORD", "Hr123!")
    checks = 0

    try:
        status, response = call(base_url, "GET", "/api/health")
        health = data(response)
        expect(
            "health",
            status,
            200,
            response,
            {
                "status": health.get("status"),
                "dataset_ready": health.get("dataset_ready"),
                "ai_enabled": health.get("ai_enabled"),
            },
        )
        if health.get("status") != "ok" or health.get("dataset_ready") is not True:
            raise CheckFailed("health: application or dataset is not ready")
        checks += 1

        employee_token = login(base_url, "employee.demo", employee_password)
        checks += 1
        try:
            profile = read_check(base_url, employee_token, "employee-profile", "/api/me/profile")
            recommendations = read_check(
                base_url, employee_token, "recommendations", "/api/me/recommendations"
            )
            plan = read_check(base_url, employee_token, "career-plan", "/api/me/plan")
            season = read_check(base_url, employee_token, "career-pass", "/api/me/season")
            ai_status = read_check(
                base_url, employee_token, "assistant-status", "/api/me/assistant/status"
            )
            checks += 5

            status, response = call(base_url, "GET", "/api/hr/overview", employee_token)
            expect("employee-cannot-read-hr", status, 403, response)
            checks += 1

            if not isinstance(recommendations.get("items", []), list):
                raise CheckFailed("recommendations: items is not a list")
            if not isinstance(plan.get("items", []), list):
                raise CheckFailed("career-plan: items is not a list")
            if not isinstance(profile.get("progress", {}), dict):
                raise CheckFailed("employee-profile: progress is missing")
            if not isinstance(season.get("season", {}), dict):
                raise CheckFailed("career-pass: season is missing")
            if ai_status.get("fallback") != "local":
                raise CheckFailed("assistant-status: local fallback is not declared")

            if args.with_openai:
                status, response = call(
                    base_url,
                    "POST",
                    "/api/me/assistant/explain",
                    employee_token,
                    {"question": "why"},
                )
                explanation = data(response)
                expect(
                    "assistant-explanation",
                    status,
                    200,
                    response,
                    {"mode": explanation.get("mode"), "provider": explanation.get("provider")},
                )
                if explanation.get("mode") not in {"llm", "template"}:
                    raise CheckFailed("assistant-explanation: invalid mode")

                status, response = call(
                    base_url,
                    "POST",
                    "/api/me/assistant/plan",
                    employee_token,
                    {"focus": "balanced"},
                )
                draft = data(response)
                expect(
                    "assistant-plan-draft",
                    status,
                    200,
                    response,
                    {"mode": draft.get("mode"), "items": len(draft.get("items", []))},
                )
                if draft.get("mode") not in {"llm", "template"}:
                    raise CheckFailed("assistant-plan-draft: invalid mode")
                checks += 2
        finally:
            logout(base_url, employee_token)
            checks += 1

        hr_token = login(base_url, "hr.demo", hr_password)
        checks += 1
        try:
            overview = read_check(base_url, hr_token, "hr-overview", "/api/hr/overview")
            directory = read_check(base_url, hr_token, "hr-directory", "/api/hr/employees")
            checks += 2
            if not isinstance(overview, dict) or not isinstance(directory.get("items", []), list):
                raise CheckFailed("HR response has an unexpected shape")
        finally:
            logout(base_url, hr_token)
            checks += 1
    except CheckFailed as error:
        print(
            json.dumps(
                {"result": "FAIL", "checks_passed": checks, "error": str(error)},
                ensure_ascii=False,
            ),
            file=sys.stderr,
        )
        return 1

    print(json.dumps({"result": "PASS", "checks_passed": checks}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
