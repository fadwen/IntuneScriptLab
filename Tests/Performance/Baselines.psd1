# The baselines of the performance gate (CIC-13, Build/Test-PerformanceBaseline.ps1): for each
# runner, the median seconds and the megabytes kept of each reader at a log size, recorded with
# Test-PerformanceBaseline.ps1 -Record from the hosted runs named in the comment of each runner.
# A median more than the margin above its baseline fails the build; the margin is the spread the
# recorded runs showed, with room to spare.
@{
    Margin = @{
        Seconds = 0.5
        Megabytes = 0.5
    }

    Runners = @{
    }
}
