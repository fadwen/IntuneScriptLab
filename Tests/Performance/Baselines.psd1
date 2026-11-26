# The baselines of the performance gate (CIC-13, Build/Test-PerformanceBaseline.ps1): for each
# runner, the median seconds and the megabytes kept of each reader at 10,000 lines, recorded with
# Test-PerformanceBaseline.ps1 -Record from the hosted runs named in the comment of each runner.
# A median more than the margin above its baseline fails the build.
#
# The margins come from the first recorded runs. Three jobs on win25-vs2026, three runs of the
# suite each: the medians of the jobs were 0.90 to 1.10 seconds for the log reader and 1.24 to
# 1.69 for the timeline, up to a third apart, and the first run of each job took twice as long as
# the other two, which the median leaves out. The memory kept was the same in every run. A median
# twice its baseline, or a quarter more memory, is therefore a change in the code, not the runner.
@{
    Margin = @{
        Seconds = 1.0
        Megabytes = 0.25
    }

    Runners = @{
        # Quality Gates runs 45726300466, 45726303917 and 45726307359, 2026-11-26; the medians of
        # the middle one
        'win25-vs2026/X64/7.6' = @{
            'Get-IntuneAgentLog/10000' = @{ Seconds = 1.06; Megabytes = 25.7 }
            'Get-IntuneAgentTimeline/10000' = @{ Seconds = 1.63; Megabytes = 20.2 }
        }
    }
}
