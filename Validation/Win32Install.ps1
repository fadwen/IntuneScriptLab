# Install/uninstall script packaged into the Win32 test app. The PROBE marker line below is replaced
# with Probe.ps1 at packaging time (a param block has to come first, so the probe can't be prepended).
# Every experiment shares this one package; the app's install command passes its own name.
# Keep the marker text out of these comments: the replace hits the first occurrence.
param(
    [string]$Experiment = 'W32',
    [switch]$Uninstall
)

# --PROBE--

Write-ProbeRecord -Experiment $Experiment -Phase $(if ($Uninstall) { 'uninstall' } else { 'install' })
$lab = 'C:\ProgramData\IntuneScriptLab'
if ($Uninstall) {
    # The uninstall-intent experiment's detection reads this: present means "no longer installed"
    New-Item -ItemType File -Path "$lab\$Experiment.uninstalled" -Force | Out-Null
    Remove-Item -Path "$lab\$Experiment.installed" -Force -ErrorAction SilentlyContinue
}
else {
    # Marker-based detections (dependencies, supersedence) read this as "installed"
    New-Item -ItemType File -Path "$lab\$Experiment.installed" -Force | Out-Null
    Remove-Item -Path "$lab\$Experiment.uninstalled" -Force -ErrorAction SilentlyContinue
}
exit 0
