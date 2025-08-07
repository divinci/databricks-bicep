BeforeAll {
    # Import required modules
    Import-Module Pester -Force
    
    # Test configuration
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
}

Describe "Databricks Job Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a simple notebook job" {
            $templateFile = "$PSScriptRoot/../modules/job.bicep"
            $parameters = @{
                JobName = "test-notebook-job-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                JobSettings = @{
                    notebook_task = @{
                        notebook_path = "/Shared/test-notebook"
                        base_parameters = @{
                            param1 = "value1"
                        }
                    }
                    new_cluster = @{
                        spark_version = "13.3.x-scala2.12"
                        node_type_id = "Standard_DS3_v2"
                        num_workers = 1
                    }
                }
            }
            
            # Deploy the template
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.JobId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.JobName.Value | Should -Be $parameters.JobName
            $deployment.Outputs.TimeoutSeconds.Value | Should -Be 3600
            $deployment.Outputs.MaxConcurrentRuns.Value | Should -Be 1
            
            # Store job ID for cleanup
            $script:CreatedJobId = $deployment.Outputs.JobId.Value
        }
        
        It "Should create a JAR job with schedule" {
            $templateFile = "$PSScriptRoot/../modules/job.bicep"
            $parameters = @{
                JobName = "test-jar-job-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                TimeoutSeconds = 7200
                MaxConcurrentRuns = 2
                JobSettings = @{
                    spark_jar_task = @{
                        main_class_name = "com.example.MainClass"
                        parameters = @("arg1", "arg2")
                    }
                    new_cluster = @{
                        spark_version = "13.3.x-scala2.12"
                        node_type_id = "Standard_DS3_v2"
                        num_workers = 2
                    }
                    libraries = @(
                        @{
                            jar = "dbfs:/mnt/libraries/example.jar"
                        }
                    )
                }
                Schedule = @{
                    quartz_cron_expression = "0 0 12 * * ?"
                    timezone_id = "UTC"
                }
                EmailNotifications = @{
                    on_success = @("success@example.com")
                    on_failure = @("failure@example.com")
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.JobId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.TimeoutSeconds.Value | Should -Be $parameters.TimeoutSeconds
            $deployment.Outputs.MaxConcurrentRuns.Value | Should -Be $parameters.MaxConcurrentRuns
            
            # Store job ID for cleanup
            $script:CreatedScheduledJobId = $deployment.Outputs.JobId.Value
        }
        
        It "Should create a Python wheel job" {
            $templateFile = "$PSScriptRoot/../modules/job.bicep"
            $parameters = @{
                JobName = "test-python-job-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                JobSettings = @{
                    python_wheel_task = @{
                        package_name = "my_package"
                        entry_point = "main"
                        parameters = @("--input", "/tmp/input", "--output", "/tmp/output")
                    }
                    new_cluster = @{
                        spark_version = "13.3.x-scala2.12"
                        node_type_id = "Standard_DS3_v2"
                        num_workers = 1
                    }
                    libraries = @(
                        @{
                            whl = "dbfs:/mnt/libraries/my_package-1.0.0-py3-none-any.whl"
                        }
                    )
                }
                Tags = @{
                    Environment = "Test"
                    JobType = "PythonWheel"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.JobId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.JobName.Value | Should -Be $parameters.JobName
            
            # Store job ID for cleanup
            $script:CreatedPythonJobId = $deployment.Outputs.JobId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty job name" {
            $templateFile = "$PSScriptRoot/../modules/job.bicep"
            $parameters = @{
                JobName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                JobSettings = @{
                    notebook_task = @{
                        notebook_path = "/Shared/test-notebook"
                    }
                }
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
        
        It "Should fail with invalid timeout" {
            $templateFile = "$PSScriptRoot/../modules/job.bicep"
            $parameters = @{
                JobName = "test-invalid-timeout-job"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                TimeoutSeconds = -1
                JobSettings = @{
                    notebook_task = @{
                        notebook_path = "/Shared/test-notebook"
                    }
                }
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
    # Cleanup created jobs
    if ($script:CreatedJobId) {
        Write-Host "Cleaning up job: $($script:CreatedJobId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/jobs/delete" `
                -Body "{`"job_id`": $($script:CreatedJobId)}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup job $($script:CreatedJobId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedScheduledJobId) {
        Write-Host "Cleaning up scheduled job: $($script:CreatedScheduledJobId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/jobs/delete" `
                -Body "{`"job_id`": $($script:CreatedScheduledJobId)}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup scheduled job $($script:CreatedScheduledJobId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedPythonJobId) {
        Write-Host "Cleaning up Python job: $($script:CreatedPythonJobId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/jobs/delete" `
                -Body "{`"job_id`": $($script:CreatedPythonJobId)}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup Python job $($script:CreatedPythonJobId): $($_.Exception.Message)"
        }
    }
}
