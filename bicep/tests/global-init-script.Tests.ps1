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

Describe "Databricks Global Init Script Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a global init script with default content" {
            $templateFile = "$PSScriptRoot/../modules/global-init-script.bicep"
            $parameters = @{
                ScriptName = "test-default-script-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Enabled = $true
                Position = 1
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ScriptId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.ScriptName.Value | Should -Be $parameters.ScriptName
            $deployment.Outputs.Enabled.Value | Should -Be $true
            $deployment.Outputs.Position.Value | Should -Be 1
            $deployment.Outputs.CreatedBy.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedDefaultScriptId = $deployment.Outputs.ScriptId.Value
        }
        
        It "Should create a global init script with custom content" {
            $templateFile = "$PSScriptRoot/../modules/global-init-script.bicep"
            $customScript = @"
#!/bin/bash
# Custom global init script for testing
echo "Custom script executed at `$(date)"
apt-get update
apt-get install -y htop
"@
            $encodedScript = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($customScript))
            
            $parameters = @{
                ScriptName = "test-custom-script-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Content = $encodedScript
                Enabled = $false
                Position = 2
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ScriptName.Value | Should -Be $parameters.ScriptName
            $deployment.Outputs.Enabled.Value | Should -Be $false
            $deployment.Outputs.Position.Value | Should -Be 2
            
            $script:CreatedCustomScriptId = $deployment.Outputs.ScriptId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty script name" {
            $templateFile = "$PSScriptRoot/../modules/global-init-script.bicep"
            $parameters = @{
                ScriptName = ""
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
}

AfterAll {
    if ($script:CreatedDefaultScriptId) {
        Write-Host "Cleaning up default global init script: $($script:CreatedDefaultScriptId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/global-init-scripts/$($script:CreatedDefaultScriptId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup default global init script $($script:CreatedDefaultScriptId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedCustomScriptId) {
        Write-Host "Cleaning up custom global init script: $($script:CreatedCustomScriptId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/global-init-scripts/$($script:CreatedCustomScriptId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup custom global init script $($script:CreatedCustomScriptId): $($_.Exception.Message)"
        }
    }
}
