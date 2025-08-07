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

Describe "Databricks Instance Profile Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should add an instance profile with validation" {
            $templateFile = "$PSScriptRoot/../modules/instance-profile.bicep"
            $parameters = @{
                InstanceProfileName = "test-instance-profile-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                InstanceProfileArn = "arn:aws:iam::123456789012:instance-profile/test-databricks-instance-profile"
                SkipValidation = $false
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.InstanceProfileArn.Value | Should -Be $parameters.InstanceProfileArn
            $deployment.Outputs.IsMetaInstanceProfile.Value | Should -BeOfType [bool]
            
            $script:CreatedInstanceProfileArn = $deployment.Outputs.InstanceProfileArn.Value
        }
        
        It "Should add an instance profile without validation" {
            $templateFile = "$PSScriptRoot/../modules/instance-profile.bicep"
            $parameters = @{
                InstanceProfileName = "test-instance-profile-no-validation-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                InstanceProfileArn = "arn:aws:iam::123456789012:instance-profile/test-databricks-no-validation"
                SkipValidation = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.InstanceProfileArn.Value | Should -Be $parameters.InstanceProfileArn
            
            $script:CreatedInstanceProfileArnNoValidation = $deployment.Outputs.InstanceProfileArn.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty instance profile name" {
            $templateFile = "$PSScriptRoot/../modules/instance-profile.bicep"
            $parameters = @{
                InstanceProfileName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                InstanceProfileArn = "arn:aws:iam::123456789012:instance-profile/test-databricks-instance-profile"
                SkipValidation = $false
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
        
        It "Should fail with invalid instance profile ARN format" {
            $templateFile = "$PSScriptRoot/../modules/instance-profile.bicep"
            $parameters = @{
                InstanceProfileName = "test-invalid-arn"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                InstanceProfileArn = "invalid-arn-format"
                SkipValidation = $false
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
        # Cleanup instance profiles
        if ($script:CreatedInstanceProfileArn) {
            Write-Host "Cleaning up instance profile: $($script:CreatedInstanceProfileArn)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/instance-profiles/remove" `
                    -Body (@{ instance_profile_arn = $script:CreatedInstanceProfileArn } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup instance profile $($script:CreatedInstanceProfileArn): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedInstanceProfileArnNoValidation) {
            Write-Host "Cleaning up instance profile (no validation): $($script:CreatedInstanceProfileArnNoValidation)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/instance-profiles/remove" `
                    -Body (@{ instance_profile_arn = $script:CreatedInstanceProfileArnNoValidation } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup instance profile $($script:CreatedInstanceProfileArnNoValidation): $($_.Exception.Message)"
            }
        }
    }
}
