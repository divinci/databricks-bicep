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

Describe "Databricks Compliance Security Profile Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a compliance security profile with SOC2 standards" {
            $templateFile = "$PSScriptRoot/../modules/compliance-security-profile.bicep"
            $parameters = @{
                ProfileName = "test-compliance-profile-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $true
                ComplianceStandards = @("SOC2", "HIPAA")
                SecurityControls = @{
                    enforce_cluster_policies = $true
                    require_mfa = $true
                    audit_logging = $true
                    data_encryption = $true
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ProfileName.Value | Should -Be $parameters.ProfileName
            $deployment.Outputs.ProfileId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.IsEnabled.Value | Should -Be $true
            $deployment.Outputs.ComplianceStandards.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.SecurityControls.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.UpdatedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedProfileId = $deployment.Outputs.ProfileId.Value
        }
        
        It "Should create a compliance security profile with PCI DSS standards" {
            $templateFile = "$PSScriptRoot/../modules/compliance-security-profile.bicep"
            $parameters = @{
                ProfileName = "test-pci-profile-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $true
                ComplianceStandards = @("PCI_DSS")
                SecurityControls = @{
                    enforce_cluster_policies = $true
                    require_mfa = $true
                    network_isolation = $true
                    access_logging = $true
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ComplianceStandards.Value | Should -Match "PCI_DSS"
            
            $script:CreatedPciProfileId = $deployment.Outputs.ProfileId.Value
        }
        
        It "Should disable a compliance security profile" {
            $templateFile = "$PSScriptRoot/../modules/compliance-security-profile.bicep"
            $parameters = @{
                ProfileName = "test-disabled-profile-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $false
                ComplianceStandards = @()
                SecurityControls = @{}
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.IsEnabled.Value | Should -Be $false
            
            $script:CreatedDisabledProfileId = $deployment.Outputs.ProfileId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty profile name" {
            $templateFile = "$PSScriptRoot/../modules/compliance-security-profile.bicep"
            $parameters = @{
                ProfileName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $true
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
        # Cleanup compliance security profiles
        if ($script:CreatedProfileId) {
            Write-Host "Cleaning up compliance security profile: $($script:CreatedProfileId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/workspace/compliance-security-profiles/$($script:CreatedProfileId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup compliance security profile $($script:CreatedProfileId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedPciProfileId) {
            Write-Host "Cleaning up PCI compliance security profile: $($script:CreatedPciProfileId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/workspace/compliance-security-profiles/$($script:CreatedPciProfileId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup PCI compliance security profile $($script:CreatedPciProfileId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedDisabledProfileId) {
            Write-Host "Cleaning up disabled compliance security profile: $($script:CreatedDisabledProfileId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/workspace/compliance-security-profiles/$($script:CreatedDisabledProfileId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup disabled compliance security profile $($script:CreatedDisabledProfileId): $($_.Exception.Message)"
            }
        }
    }
}
