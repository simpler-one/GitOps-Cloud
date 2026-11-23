terraform{
    backend "s3"  {
        bucket = "gitops-eks-data"
        key =  "gitops-eks.tfstate"
        region = "ap-south-1"
        use_lockfile = "true"
        encrypt = "true"
    }
}