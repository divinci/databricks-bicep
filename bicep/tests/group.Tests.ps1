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

Describe "Databricks Group Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic group" {
            $templateFile = "$PSScriptRoot/../modules/group.bicep"
            $parameters = @{
                GroupName = "test-basic-group-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.GroupId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.GroupName.Value | Should -Be $parameters.GroupName
            $deployment.Outputs.MemberCount.Value | Should -Be 0
            
            $script:CreatedBasicGroupId = $deployment.Outputs.GroupId.Value
        }
        
        It "Should create a group with display name and entitlements" {
            $templateFile = "$PSScriptRoot/../modules/group.bicep"
            $parameters = @{
                GroupName = "test-advanced-group-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                DisplayName = "Test Advanced Group Display Name"
                Entitlements = @("allow-cluster-create", "allow-instance-pool-create")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.DisplayName.Value | Should -Be $parameters.DisplayName
            
            $script:CreatedAdvancedGroupId = $deployment.Outputs.GroupId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty group name" {
            $templateFile = "$PSScriptRoot/../modules/group.bicep"
            $parameters = @{
                GroupName = ""
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
    if ($script:CreatedBasicGroupId) {
        Write-Host "Cleaning up basic group: $($script:CreatedBasicGroupId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/preview/scim/v2/Groups/$($script:CreatedBasicGroupId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup basic group $($script:CreatedBasicGroupId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedAdvancedGroupId) {
        Write-Host "Cleaning up advanced group: $($script:CreatedAdvancedGroupId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/preview/scim/v2/Groups/$($script:CreatedAdvancedGroupId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup advanced group $($script:CreatedAdvancedGroupId): $($_.Exception.Message)"
        }
    }
}
