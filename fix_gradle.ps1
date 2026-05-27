# PowerShell script to patch Flutter Gradle Plugin afterEvaluate issue
# This is a workaround for the "Cannot run Project.afterEvaluate when project is already evaluated" error

Write-Host "Applying Gradle workaround for Flutter plugin..."

$gradleProperties = "android\gradle.properties"

# Ensure all necessary properties are set
$content = Get-Content $gradleProperties -Raw
$newContent = $content

# Add properties if they don't exist
if ($content -notmatch "org.gradle.configuration-cache.enabled") {
    $newContent += "`n# Disable configuration cache to avoid afterEvaluate issues`norg.gradle.configuration-cache.enabled=false`n"
}

if ($content -notmatch "org.gradle.workers.max") {
    $newContent += "# Ensure single thread evaluation`norg.gradle.workers.max=1`n"
}

if ($content -notmatch "org.gradle.parallel=false") {
    $newContent += "# Disable parallel execution`norg.gradle.parallel=false`n"
}

Set-Content -Path $gradleProperties -Value $newContent

Write-Host "Gradle properties updated successfully!"
Write-Host "Now trying build with workaround..."

