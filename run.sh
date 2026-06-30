aws ecs run-task `
    --region ap-southeast-1 `
    --cluster etl-job `
    --task-definition etl-job `
    --launch-type FARGATE `
    --network-configuration "awsvpcConfiguration={subnets=[subnet-079be5bb930335030,subnet-095db610e6db58ed1],securityGroups=[sg-0f7283514661696e7],assignPublicIp=ENABLED}"

aws ssm put-parameter `
    --name "/etl-job/nr-license-key" `
    --value "129d67ff8ebbb42014c4b1d7ee5d41ace9c6NRAL" `
    --type SecureString `
    --overwrite `
    --region ap-southeast-1

aws ecs run-task `
   --region ap-southeast-1 `
   --cluster etl-job `
   --task-definition etl-job `
   --launch-type FARGATE `
   --network-configuration 'awsvpcConfiguration={subnets=[subnet-01ad82d07e85faf58,subnet-0b13a76a565eee40d],securityGroups=[sg-0076d76150ae29146],assignPublicIp=ENABLED}'
