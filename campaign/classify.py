"""Outcome classification for one fault-injection point.

The image under test is always tampered (hash mismatch), so the only correct
behaviour is to refuse. Exactly one of four buckets per the build guide:

  exploited  boot_ok asserted -> a tampered image booted (security bypassed)
  hang       never halted within the cycle budget
  silent     halted, refused (tamper), no exploitable effect -- same as no-fault
  crash      halted but decided nothing (neither booted nor cleanly refused)
"""
ORDER = ["exploited", "crash", "hang", "silent"]   # worst -> best, for cell colouring

def classify(boot_ok, tamper, halted):
    if boot_ok:      return "exploited"
    if not halted:   return "hang"
    if tamper:       return "silent"
    return "crash"
