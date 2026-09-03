"""The time, pinned in the corner.

Twelve lines of duty and a docstring. If this is longer than a person will
read, the SDK has failed at its actual job — see services.md §3.
"""
import time

from cogiti.service import Service, every

svc = Service()


@every(10)
def tick():
    svc.show(kind="text", style="headline", text=time.strftime("%H:%M"))


svc.run()
