subnet_config = {
  public_1 = {
    cidr = "10.0.1.0/24"
    az   = "ap-south-1a"
    type = "public"
  }
  public_2 = {
    cidr = "10.0.3.0/24"
    az   = "ap-south-1b"
    type = "public"
  }
  private_1 = {
    cidr = "10.0.2.0/24"
    az   = "ap-south-1a"
    type = "private"
  }
  private_2 = {
    cidr = "10.0.4.0/24"
    az   = "ap-south-1b"
    type = "private"
  }
}