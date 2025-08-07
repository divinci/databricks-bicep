BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
}

Describe "Databricks Workspace File Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a Python workspace file with content" {
            $templateFile = "$PSScriptRoot/../modules/workspace-file.bicep"
            $parameters = @{
                Path = "/Shared/test-python-file-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Content = "# Databricks notebook source`nprint('Hello, World!')`n# COMMAND ----------`nprint('This is a test notebook')"
                Language = "PYTHON"
                Format = "SOURCE"
                Overwrite = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Path.Value | Should -Be $parameters.Path
            $deployment.Outputs.ObjectType.Value | Should -Be "NOTEBOOK"
            $deployment.Outputs.ObjectId.Value | Should -BeGreaterThan 0
            $deployment.Outputs.Language.Value | Should -Be "PYTHON"
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.ModifiedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedPythonFilePath = $deployment.Outputs.Path.Value
        }
        
        It "Should create a SQL workspace file" {
            $templateFile = "$PSScriptRoot/../modules/workspace-file.bicep"
            $parameters = @{
                Path = "/Shared/test-sql-file-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Content = "-- Databricks notebook source`nSELECT 'Hello, SQL!' as greeting;`n-- COMMAND ----------`nSHOW TABLES;"
                Language = "SQL"
                Format = "SOURCE"
                Overwrite = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Language.Value | Should -Be "SQL"
            
            $script:CreatedSqlFilePath = $deployment.Outputs.Path.Value
        }
        
        It "Should create a Scala workspace file" {
            $templateFile = "$PSScriptRoot/../modules/workspace-file.bicep"
            $parameters = @{
                Path = "/Shared/test-scala-file-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Content = "// Databricks notebook source`nprintln(`"Hello, Scala!`")`n// COMMAND ----------`nval df = spark.range(10)"
                Language = "SCALA"
                Format = "SOURCE"
                Overwrite = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Language.Value | Should -Be "SCALA"
            
            $script:CreatedScalaFilePath = $deployment.Outputs.Path.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty path" {
            $templateFile = "$PSScriptRoot/../modules/workspace-file.bicep"
            $parameters = @{
                Path = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Content = "print('test')"
                Language = "PYTHON"
            }
            
            { 
                New-AzResourceGroupDeployment `
                    -ResourceGroupName $script:TestResourceGroup `
                    -TemplateFile $templateFile `
                    -TemplateParameterObject $parameters `
                    -Mode Incremental `
                    -ErrorAction Stop
            } | Should -Throw
        }
        
        It "Should fail with invalid language" {
            $templateFile = "$PSScriptRoot/../modules/workspace-file.bicep"
            $parameters = @{
                Path = "/Shared/test-file"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Content = "test content"
                Language = "INVALID"
            }
            
            { 
                New-AzResourceGroupDeployment `
                    -ResourceGroupName $script:TestResourceGroup `
                    -TemplateFile $templateFile `
                    -TemplateParameterObject $parameters `
                    -Mode Incremental `
                    -ErrorAction Stop
            } | Should -Throw
        }
    }
    
    AfterAll {
        # Cleanup workspace files
        if ($script:CreatedPythonFilePath) {
            Write-Host "Cleaning up Python workspace file: $($script:CreatedPythonFilePath)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/workspace/delete" `
                    -Body (@{ path = $script:CreatedPythonFilePath; recursive = $false } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup Python workspace file $($script:CreatedPythonFilePath): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedSqlFilePath) {
            Write-Host "Cleaning up SQL workspace file: $($script:CreatedSqlFilePath)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/workspace/delete" `
                    -Body (@{ path = $script:CreatedSqlFilePath; recursive = $false } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup SQL workspace file $($script:CreatedSqlFilePath): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedScalaFilePath) {
            Write-Host "Cleaning up Scala workspace file: $($script:CreatedScalaFilePath)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/workspace/delete" `
                    -Body (@{ path = $script:CreatedScalaFilePath; recursive = $false } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup Scala workspace file $($script:CreatedScalaFilePath): $($_.Exception.Message)"
            }
        }
    }
}
