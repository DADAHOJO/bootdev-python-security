# Python Debugging Notes (Chapter 5 Aligned)

Focused debugging notes aligned to **Chapter 5: Testing and Debugging** in Boot.dev.

## What This Chapter Builds

- Unit-test mindset
- Debugging practice workflow
- Traceback/stack-trace interpretation
- Iterative learning loops

## Security-Relevant Debugging Principles

1. **Fail safely**
   - User-facing errors should be generic.
   - Internal logs can keep detail.

2. **Avoid information leakage**
   - No raw stack traces in user outputs.
   - No sensitive values in debug prints.

3. **Debug with intent**
   - Reproduce issue.
   - Narrow scope.
   - Verify with tests.

## Minimal Secure Pattern

```python
def process(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return "input not found"
    except Exception:
        return "processing error"
```

## Traceback Review Checklist

- Error type identified?
- Trigger input identified?
- Is output leaking internals?
- Is there a regression test for this case?

## Daily Practice Loop

1. Write/adjust one test.
2. Reproduce bug.
3. Fix smallest root cause.
4. Re-run tests.
5. Commit with a clear message.

## Quick Security Checklist Before Commit

- [ ] No debug secrets in logs
- [ ] No stack traces in user-facing strings
- [ ] Failure paths tested
- [ ] Commit message describes bug class and fix

## Latest Learning Sync

- **Date:** May 16, 2026
- **Chapter focus:** Chapter 10 - Dictionaries
- **Security mapping:** A09: Security Logging and Monitoring Failures

