import base64
import gzip
import json
import logging
import os
import urllib.error
import urllib.request

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

_NR_LOG_API = "https://log-api.newrelic.com/log/v1"


def handler(event, context):
    log.info("Lambda invoked")

    raw     = base64.b64decode(event["awslogs"]["data"])
    payload = json.loads(gzip.decompress(raw))

    log_group  = payload.get("logGroup", "")
    log_stream = payload.get("logStream", "")
    log_events = payload.get("logEvents", [])

    log.info("Received %d log event(s) from %s / %s", len(log_events), log_group, log_stream)

    if not log_events:
        log.info("No log events — nothing to forward")
        return

    license_key = os.environ.get("NEW_RELIC_LICENSE_KEY", "")
    if not license_key:
        log.error("NEW_RELIC_LICENSE_KEY env var is missing or empty — cannot forward logs")
        raise RuntimeError("NEW_RELIC_LICENSE_KEY not set")

    body = json.dumps([
        {
            "common": {
                "attributes": {
                    "aws.logGroup":  log_group,
                    "aws.logStream": log_stream,
                }
            },
            "logs": [
                {"timestamp": e["timestamp"], "message": e["message"]}
                for e in log_events
            ],
        }
    ]).encode()

    log.info("POSTing %d bytes to New Relic Log API", len(body))

    req = urllib.request.Request(
        _NR_LOG_API,
        data=body,
        headers={
            "Content-Type":  "application/json",
            "X-License-Key": license_key,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            status       = resp.status
            resp_body    = resp.read().decode()
            log.info("New Relic Log API responded: HTTP %d — %s", status, resp_body)
            if status not in (200, 202):
                raise RuntimeError(f"New Relic Log API returned HTTP {status}: {resp_body}")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        log.error("New Relic Log API HTTP error %d: %s", e.code, err_body)
        raise
    except urllib.error.URLError as e:
        log.error("Network error reaching New Relic Log API: %s", e.reason)
        raise

    log.info("Done — %d log event(s) forwarded successfully", len(log_events))
