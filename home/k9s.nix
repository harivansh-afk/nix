{ ... }:
{
  programs.k9s = {
    enable = true;
    views."v1/pods".columns = [
      "NAME"
      "USER:.metadata.labels.handle"
      "STATUS"
      "READY"
      "AGE"
    ];
  };
}
