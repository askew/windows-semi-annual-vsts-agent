# VSTS Agent Set up for Building Windows Containers

When building Windows containers images based on the Windows Server Semi-Annual Channel the server OS must match that of the base container image. Otherwise you get the error

```
failure in a Windows system call: The operating system of the container does not match the operating system of the host.
```

The Hosted agents available in VSTS are based on the Long-Term Servicing Channel for Windows Server so you cannot use these to build containers based on `microsoft/nanoserver:1709` or `microsoft/nanoserver:1803`.

This PowerShell script can be used to configure Docker and the VSTS agent on a Windows Server VM based the image in Azure.