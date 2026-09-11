# Classifies uncommitted git changes into logical groups (Backend, Frontend, Config, Docs)
# Run from repository root: powershell -ExecutionPolicy Bypass -File .agents/skills/group-commits/scripts/classify_changes.ps1

$gitStatus = git status --porcelain
if (-not $gitStatus) {
    Write-Host "No uncommitted changes found. Working tree clean." -ForegroundColor Green
    exit 0
}

$groups = [ordered]@{
    "Backend: Schemas & Database" = [System.Collections.Generic.List[string]]::new()
    "Backend: API Routes & Logic" = [System.Collections.Generic.List[string]]::new()
    "Backend: Config, Scripts & Tests" = [System.Collections.Generic.List[string]]::new()
    "Backend: Cloud Functions & Rules" = [System.Collections.Generic.List[string]]::new()
    
    "Frontend: Services & Providers" = [System.Collections.Generic.List[string]]::new()
    "Frontend: Screens & Navigation" = [System.Collections.Generic.List[string]]::new()
    "Frontend: Widgets & Components" = [System.Collections.Generic.List[string]]::new()
    "Frontend: Localization (L10n)" = [System.Collections.Generic.List[string]]::new()
    "Frontend: Core & Main" = [System.Collections.Generic.List[string]]::new()
    "Frontend: Platform Native & Assets" = [System.Collections.Generic.List[string]]::new()
    "Frontend: Tests" = [System.Collections.Generic.List[string]]::new()
    
    "DevOps & Global Config" = [System.Collections.Generic.List[string]]::new()
    "Documentation" = [System.Collections.Generic.List[string]]::new()
    "Build Artifacts & Untracked (Review/Ignore)" = [System.Collections.Generic.List[string]]::new()
    "Other / Unclassified" = [System.Collections.Generic.List[string]]::new()
}

foreach ($line in ($gitStatus -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $statusCode = $line.Substring(0, 2)
    $filePath = $line.Substring(3).Trim()
    
    # Handle renames e.g. "R  old -> new"
    if ($filePath -match '->') {
        $filePath = ($filePath -split '->')[-1].Trim()
    }
    
    $normalized = $filePath.Replace('\', '/')

    # Filter build / dist artifacts
    if ($normalized -match '(^|/)dist/' -or $normalized -match '(^|/)build/' -or $normalized -match '\.dart_tool/' -or $normalized -match '(^|/)uploads/') {
        $groups["Build Artifacts & Untracked (Review/Ignore)"].Add("$statusCode $filePath")
        continue
    }

    # Backend
    if ($normalized -match '^backend-hono/src/db/') {
        $groups["Backend: Schemas & Database"].Add("$statusCode $filePath")
    }
    elseif ($normalized -match '^backend-hono/src/routes/' -or $normalized -eq 'backend-hono/src/app.ts') {
        $groups["Backend: API Routes & Logic"].Add("$statusCode $filePath")
    }
    elseif ($normalized -match '^backend-hono/test/' -or $normalized -match '^backend-hono/src/scripts/' -or $normalized -match '^backend-hono/(package|tsconfig|drizzle)') {
        $groups["Backend: Config, Scripts & Tests"].Add("$statusCode $filePath")
    }
    elseif ($normalized -match '^backend-hono/') {
        $groups["Backend: Config, Scripts & Tests"].Add("$statusCode $filePath")
    }
    elseif ($normalized -match '^functions/' -or $normalized -match '^supabase/' -or $normalized -match '\.rules(\.json)?$') {
        $groups["Backend: Cloud Functions & Rules"].Add("$statusCode $filePath")
    }

    # Frontend
    elseif ($normalized -match '^lib/src/services/' -or $normalized -match '^lib/src/providers/') {
        $groups["Frontend: Services & Providers"].Add("$statusCode $filePath")
    }
    elseif ($normalized -match '^lib/src/features/screens/') {
        $groups["Frontend: Screens & Navigation"].Add("$statusCode $filePath")
    }
    elseif ($normalized -match '^lib/src/features/widgets/') {
        $groups["Frontend: Widgets & Components"].Add("$statusCode $filePath")
    }
    elseif ($normalized -match '^lib/src/l10n/') {
        $groups["Frontend: Localization (L10n)"].Add("$statusCode $filePath")
    }
    elseif ($normalized -eq 'lib/main.dart' -or $normalized -match '^lib/src/core/') {
        $groups["Frontend: Core & Main"].Add("$statusCode $filePath")
    }
    elseif ($normalized -match '^lib/') {
        $groups["Frontend: Core & Main"].Add("$statusCode $filePath")
    }
    elseif ($normalized -match '^(android|ios|web|windows|macos|linux|assets)/') {
        $groups["Frontend: Platform Native & Assets"].Add("$statusCode $filePath")
    }
    elseif ($normalized -match '^test/') {
        $groups["Frontend: Tests"].Add("$statusCode $filePath")
    }

    # Documentation
    elseif ($normalized -match '\.(md|txt|docx)$' -or $normalized -match '^docs/') {
        $groups["Documentation"].Add("$statusCode $filePath")
    }

    # Config / Root
    elseif ($normalized -match '(ecosystem\.config\.json|firebase\.json|\.env|analysis_options\.yaml|pubspec\.(yaml|lock)|\.gitignore)') {
        $groups["DevOps & Global Config"].Add("$statusCode $filePath")
    }
    else {
        $groups["Other / Unclassified"].Add("$statusCode $filePath")
    }
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "       UNCOMMITTED CHANGES SUMMARY       " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

foreach ($groupName in $groups.Keys) {
    $items = $groups[$groupName]
    if ($items.Count -gt 0) {
        Write-Host "`n[$groupName] ($($items.Count) files):" -ForegroundColor Yellow
        foreach ($item in $items) {
            Write-Host "  $item"
        }
    }
}
Write-Host "`n"
