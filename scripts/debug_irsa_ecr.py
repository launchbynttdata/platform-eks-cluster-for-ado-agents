#!/usr/bin/env python3
"""Append NDJSON debug lines for IRSA + ECR auth checks (run inside agent pod or with same creds as pipeline)."""
# region agent log
import json
import os
import subprocess
import sys
import time

LOG_PATH = os.path.join(
    os.path.dirname(__file__), "..", ".cursor", "debug-ffee74.log"
)
SESSION = "ffee74"
REGION = os.environ.get("AWS_DEFAULT_REGION") or os.environ.get("AWS_REGION") or "us-west-2"
# Set DEBUG_IRSA_CONTEXT=buildkit when running inside a buildkitd pod (verification).
DEBUG_CTX = os.environ.get("DEBUG_IRSA_CONTEXT", "")


def emit(hypothesis_id: str, location: str, message: str, data: dict) -> None:
    if DEBUG_CTX:
        data = {**data, "debugContext": DEBUG_CTX}
    line = {
        "sessionId": SESSION,
        "timestamp": int(time.time() * 1000),
        "location": location,
        "message": message,
        "data": data,
        "hypothesisId": hypothesis_id,
    }
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    with open(LOG_PATH, "a", encoding="ascii") as f:
        f.write(json.dumps(line, separators=(",", ":")) + "\n")


def main() -> int:
    # H1: caller identity (wrong SA / IRSA => often node role or error)
    try:
        out = subprocess.run(
            ["aws", "sts", "get-caller-identity", "--output", "json"],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        if out.returncode == 0:
            ident = json.loads(out.stdout)
            emit(
                "H1",
                "debug_irsa_ecr.py:caller",
                "sts get-caller-identity ok",
                {
                    "arn": ident.get("Arn", ""),
                    "account": ident.get("Account", ""),
                    "userId": ident.get("UserId", ""),
                },
            )
        else:
            emit(
                "H1",
                "debug_irsa_ecr.py:caller",
                "sts get-caller-identity failed",
                {"returncode": out.returncode, "stderr": (out.stderr or "")[:500]},
            )
    except Exception as e:
        emit("H1", "debug_irsa_ecr.py:caller", "sts exception", {"error": str(e)[:500]})

    # H2: ECR registry auth API (requires ecr:GetAuthorizationToken on identity policy)
    try:
        out = subprocess.run(
            [
                "aws",
                "ecr",
                "get-login-password",
                "--region",
                REGION,
            ],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        emit(
            "H2",
            "debug_irsa_ecr.py:ecr",
            "ecr get-login-password "
            + ("ok" if out.returncode == 0 else "failed"),
            {
                "region": REGION,
                "returncode": out.returncode,
                "stderr": (out.stderr or "")[:500],
            },
        )
    except Exception as e:
        emit("H2", "debug_irsa_ecr.py:ecr", "ecr exception", {"error": str(e)[:500]})

    return 0


if __name__ == "__main__":
    sys.exit(main())
# endregion
