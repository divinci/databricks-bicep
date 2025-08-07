BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestAccountId = $env:DATABRICKS_ACCOUNT_ID
    $script:TestAccountToken = $env:DATABRICKS_ACCOUNT_TOKEN
    
    if (-not $script:TestAccountId -or -not $script:TestAccountToken) {
        throw "Required environment variables DATABRICKS_ACCOUNT_ID and DATABRICKS_ACCOUNT_TOKEN must be set"
    }
}

Describe "Databricks MWS Networks Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create basic MWS network configuration" {
            $templateFile = "$PSScriptRoot/../modules/mws-networks.bicep"
            $parameters = @{
                NetworkName = "test-network-$(Get-Random)"
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                VpcId = "vpc-12345678"
                SubnetIds = @("subnet-12345678", "subnet-87654321")
                SecurityGroupIds = @("sg-12345678")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.NetworkId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.NetworkName.Value | Should -Be $parameters.NetworkName
            $deployment.Outputs.VpcId.Value | Should -Be "vpc-12345678"
            $deployment.Outputs.SubnetIds.Value | Should -Contain "subnet-12345678"
            $deployment.Outputs.SecurityGroupIds.Value | Should -Contain "sg-12345678"
            $deployment.Outputs.CreationTime.Value | Should -BeGreaterThan 0
            
            $script:CreatedNetworkId = $deployment.Outputs.NetworkId.Value
        }
        
        It "Should create MWS network with VPC endpoint" {
            $templateFile = "$PSScriptRoot/../modules/mws-networks.bicep"
            $parameters = @{
                NetworkName = "test-vpc-endpoint-network-$(Get-Random)"
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                VpcId = "vpc-87654321"
                SubnetIds = @("subnet-11111111", "subnet-22222222")
                SecurityGroupIds = @("sg-11111111", "sg-22222222")
                VpcEndpointId = "vpce-12345678"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.VpcEndpointId.Value | Should -Be "vpce-12345678"
            
            $script:CreatedVpcEndpointNetworkId = $deployment.Outputs.NetworkId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty network name" {
            $templateFile = "$PSScriptRoot/../modules/mws-networks.bicep"
            $parameters = @{
                NetworkName = ""
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                VpcId = "vpc-12345678"
                SubnetIds = @("subnet-12345678")
                SecurityGroupIds = @("sg-12345678")
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
        
        It "Should fail with empty VPC ID" {
            $templateFile = "$PSScriptRoot/../modules/mws-networks.bicep"
            $parameters = @{
                NetworkName = "test-invalid-network"
                AccountId = $script:TestAccountId
                AccountToken = $script:TestAccountToken
                VpcId = ""
                SubnetIds = @("subnet-12345678")
                SecurityGroupIds = @("sg-12345678")
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
    if ($script:CreatedNetworkId) {
        Write-Host "Cleaning up MWS network: $($script:CreatedNetworkId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestAccountToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/networks/$($script:CreatedNetworkId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl "https://accounts.cloud.databricks.com"
        }
        catch {
            Write-Warning "Failed to cleanup MWS network $($script:CreatedNetworkId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedVpcEndpointNetworkId) {
        Write-Host "Cleaning up VPC endpoint MWS network: $($script:CreatedVpcEndpointNetworkId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestAccountToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/networks/$($script:CreatedVpcEndpointNetworkId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl "https://accounts.cloud.databricks.com"
        }
        catch {
            Write-Warning "Failed to cleanup VPC endpoint MWS network $($script:CreatedVpcEndpointNetworkId): $($_.Exception.Message)"
        }
    }
}
