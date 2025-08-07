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

Describe "Databricks IP Access List Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create an ALLOW IP access list" {
            $templateFile = "$PSScriptRoot/../modules/ip-access-list.bicep"
            $parameters = @{
                Label = "test-allow-list-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ListType = "ALLOW"
                IpAddresses = @("192.168.1.0/24", "10.0.0.0/8")
                Enabled = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ListId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Label.Value | Should -Be $parameters.Label
            $deployment.Outputs.ListType.Value | Should -Be "ALLOW"
            $deployment.Outputs.Enabled.Value | Should -Be $true
            $deployment.Outputs.IpAddressCount.Value | Should -Be 2
            
            $script:CreatedAllowListId = $deployment.Outputs.ListId.Value
        }
        
        It "Should create a BLOCK IP access list" {
            $templateFile = "$PSScriptRoot/../modules/ip-access-list.bicep"
            $parameters = @{
                Label = "test-block-list-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ListType = "BLOCK"
                IpAddresses = @("172.16.0.0/12")
                Enabled = $false
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ListType.Value | Should -Be "BLOCK"
            $deployment.Outputs.Enabled.Value | Should -Be $false
            $deployment.Outputs.IpAddressCount.Value | Should -Be 1
            
            $script:CreatedBlockListId = $deployment.Outputs.ListId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty label" {
            $templateFile = "$PSScriptRoot/../modules/ip-access-list.bicep"
            $parameters = @{
                Label = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IpAddresses = @("192.168.1.0/24")
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
        
        It "Should fail with invalid list type" {
            $templateFile = "$PSScriptRoot/../modules/ip-access-list.bicep"
            $parameters = @{
                Label = "test-invalid-list"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ListType = "INVALID"
                IpAddresses = @("192.168.1.0/24")
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
    if ($script:CreatedAllowListId) {
        Write-Host "Cleaning up ALLOW IP access list: $($script:CreatedAllowListId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/ip-access-lists/$($script:CreatedAllowListId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup ALLOW IP access list $($script:CreatedAllowListId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedBlockListId) {
        Write-Host "Cleaning up BLOCK IP access list: $($script:CreatedBlockListId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/ip-access-lists/$($script:CreatedBlockListId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup BLOCK IP access list $($script:CreatedBlockListId): $($_.Exception.Message)"
        }
    }
}
