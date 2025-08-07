BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    $script:TestAccountId = $env:DATABRICKS_ACCOUNT_ID
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken -or -not $script:TestAccountId) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL, DATABRICKS_TOKEN, and DATABRICKS_ACCOUNT_ID must be set"
    }
}

Describe "Databricks MWS VPC Endpoint Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create an MWS VPC endpoint for workspace access" {
            $templateFile = "$PSScriptRoot/../modules/mws-vpc-endpoint.bicep"
            $parameters = @{
                VpcEndpointName = "test-vpc-endpoint-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                VpcEndpointId = "vpce-12345678901234567"
                Region = "us-east-1"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.VpcEndpointName.Value | Should -Be $parameters.VpcEndpointName
            $deployment.Outputs.VpcEndpointId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AwsVpcEndpointId.Value | Should -Be $parameters.VpcEndpointId
            $deployment.Outputs.Region.Value | Should -Be $parameters.Region
            $deployment.Outputs.State.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.UseCase.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AccountId.Value | Should -Be $script:TestAccountId
            
            $script:CreatedVpcEndpointId = $deployment.Outputs.VpcEndpointId.Value
        }
        
        It "Should create an MWS VPC endpoint for backend access" {
            $templateFile = "$PSScriptRoot/../modules/mws-vpc-endpoint.bicep"
            $parameters = @{
                VpcEndpointName = "test-backend-vpc-endpoint-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                VpcEndpointId = "vpce-98765432109876543"
                Region = "us-west-2"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Region.Value | Should -Be "us-west-2"
            
            $script:CreatedBackendVpcEndpointId = $deployment.Outputs.VpcEndpointId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty VPC endpoint name" {
            $templateFile = "$PSScriptRoot/../modules/mws-vpc-endpoint.bicep"
            $parameters = @{
                VpcEndpointName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                VpcEndpointId = "vpce-12345678901234567"
                Region = "us-east-1"
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
        
        It "Should fail with empty VPC endpoint ID" {
            $templateFile = "$PSScriptRoot/../modules/mws-vpc-endpoint.bicep"
            $parameters = @{
                VpcEndpointName = "test-vpc-endpoint"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                VpcEndpointId = ""
                Region = "us-east-1"
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
        # Cleanup MWS VPC endpoints
        if ($script:CreatedVpcEndpointId) {
            Write-Host "Cleaning up MWS VPC endpoint: $($script:CreatedVpcEndpointId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/vpc-endpoints/$($script:CreatedVpcEndpointId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup MWS VPC endpoint $($script:CreatedVpcEndpointId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedBackendVpcEndpointId) {
            Write-Host "Cleaning up backend MWS VPC endpoint: $($script:CreatedBackendVpcEndpointId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/vpc-endpoints/$($script:CreatedBackendVpcEndpointId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup backend MWS VPC endpoint $($script:CreatedBackendVpcEndpointId): $($_.Exception.Message)"
            }
        }
    }
}
