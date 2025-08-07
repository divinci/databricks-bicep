BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test notebook for status checking
    $script:TestNotebookPath = "/Shared/test-status-notebook-$(Get-Random)"
}

Describe "Databricks Workspace Status Bicep Module Tests" {
    BeforeAll {
        # Create a test notebook for status checking
        Write-Host "Creating test notebook for status tests: $($script:TestNotebookPath)"
        $notebookContent = @"
# Databricks notebook source
print("Test notebook for status checking")
"@
        $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
        
        $notebookConfig = @{
            path = $script:TestNotebookPath
            content = $encodedContent
            language = "PYTHON"
            format = "SOURCE"
            overwrite = $true
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/workspace/import" `
                -Body $notebookConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            Write-Host "Created test notebook successfully"
        }
        catch {
            Write-Warning "Failed to create test notebook: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should get status for root directory" {
            $templateFile = "$PSScriptRoot/../modules/workspace-status.bicep"
            $parameters = @{
                WorkspacePath = "/"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Path.Value | Should -Be "/"
            $deployment.Outputs.ObjectId.Value | Should -BeGreaterThan 0
            $deployment.Outputs.ObjectType.Value | Should -Be "DIRECTORY"
            $deployment.Outputs.Language.Value | Should -BeOfType [string]
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterOrEqual 0
            $deployment.Outputs.ModifiedAt.Value | Should -BeGreaterOrEqual 0
            $deployment.Outputs.Size.Value | Should -BeGreaterOrEqual 0
            $deployment.Outputs.Exists.Value | Should -Be $true
        }
        
        It "Should get status for test notebook" {
            if (-not $script:TestNotebookPath) {
                Set-ItResult -Skipped -Because "Test notebook creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/workspace-status.bicep"
            $parameters = @{
                WorkspacePath = $script:TestNotebookPath
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Path.Value | Should -Be $script:TestNotebookPath
            $deployment.Outputs.ObjectType.Value | Should -Be "NOTEBOOK"
            $deployment.Outputs.Language.Value | Should -Be "PYTHON"
            $deployment.Outputs.Exists.Value | Should -Be $true
            $deployment.Outputs.Size.Value | Should -BeGreaterThan 0
        }
        
        It "Should get status for Shared directory" {
            $templateFile = "$PSScriptRoot/../modules/workspace-status.bicep"
            $parameters = @{
                WorkspacePath = "/Shared"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Path.Value | Should -Be "/Shared"
            $deployment.Outputs.ObjectType.Value | Should -Be "DIRECTORY"
            $deployment.Outputs.Exists.Value | Should -Be $true
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty workspace path" {
            $templateFile = "$PSScriptRoot/../modules/workspace-status.bicep"
            $parameters = @{
                WorkspacePath = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
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
        
        It "Should fail with non-existent workspace path" {
            $templateFile = "$PSScriptRoot/../modules/workspace-status.bicep"
            $parameters = @{
                WorkspacePath = "/NonExistent/Path/That/Does/Not/Exist"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
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
        # Cleanup test notebook
        if ($script:TestNotebookPath) {
            Write-Host "Cleaning up test notebook: $($script:TestNotebookPath)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/workspace/delete" `
                    -Body (@{ path = $script:TestNotebookPath; recursive = $false } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test notebook: $($_.Exception.Message)"
            }
        }
    }
}
