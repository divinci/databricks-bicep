BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test query first for the alert
    $script:TestQueryId = ""
}

Describe "Databricks Alert Bicep Module Tests" {
    BeforeAll {
        # Create a test SQL query first
        Write-Host "Creating test SQL query for alert tests"
        $queryConfig = @{
            name = "Test Query for Alert $(Get-Random)"
            query = "SELECT 1 as test_value"
            data_source_id = "default"
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/sql/queries" `
                -Body $queryConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            $queryResult = $createResponse | ConvertFrom-Json
            $script:TestQueryId = $queryResult.id
            Write-Host "Created test query with ID: $($script:TestQueryId)"
        }
        catch {
            Write-Warning "Failed to create test query: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a basic SQL alert" {
            if (-not $script:TestQueryId) {
                Set-ItResult -Skipped -Because "Test query creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/alert.bicep"
            $parameters = @{
                AlertName = "test-alert-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                QueryId = $script:TestQueryId
                Condition = ">"
                Threshold = "0"
                Rearm = 300
                CustomSubject = "Test Alert Triggered"
                CustomBody = "Alert condition met"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AlertId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AlertName.Value | Should -Be $parameters.AlertName
            $deployment.Outputs.QueryId.Value | Should -Be $script:TestQueryId
            $deployment.Outputs.Condition.Value | Should -Be ">"
            $deployment.Outputs.Threshold.Value | Should -Be "0"
            $deployment.Outputs.Rearm.Value | Should -Be 300
            $deployment.Outputs.CustomSubject.Value | Should -Be "Test Alert Triggered"
            $deployment.Outputs.CustomBody.Value | Should -Be "Alert condition met"
            $deployment.Outputs.CreatedAt.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.State.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedAlertId = $deployment.Outputs.AlertId.Value
        }
        
        It "Should create an alert with minimal configuration" {
            if (-not $script:TestQueryId) {
                Set-ItResult -Skipped -Because "Test query creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/alert.bicep"
            $parameters = @{
                AlertName = "test-minimal-alert-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                QueryId = $script:TestQueryId
                Condition = "<="
                Threshold = "100"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Condition.Value | Should -Be "<="
            $deployment.Outputs.Threshold.Value | Should -Be "100"
            
            $script:CreatedMinimalAlertId = $deployment.Outputs.AlertId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty alert name" {
            $templateFile = "$PSScriptRoot/../modules/alert.bicep"
            $parameters = @{
                AlertName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                QueryId = "test-query-id"
                Condition = ">"
                Threshold = "0"
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
        # Cleanup alerts
        if ($script:CreatedAlertId) {
            Write-Host "Cleaning up alert: $($script:CreatedAlertId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/sql/alerts/$($script:CreatedAlertId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup alert $($script:CreatedAlertId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedMinimalAlertId) {
            Write-Host "Cleaning up minimal alert: $($script:CreatedMinimalAlertId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/sql/alerts/$($script:CreatedMinimalAlertId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup minimal alert $($script:CreatedMinimalAlertId): $($_.Exception.Message)"
            }
        }
        
        # Cleanup test query
        if ($script:TestQueryId) {
            Write-Host "Cleaning up test query: $($script:TestQueryId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/sql/queries/$($script:TestQueryId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test query: $($_.Exception.Message)"
            }
        }
    }
}
