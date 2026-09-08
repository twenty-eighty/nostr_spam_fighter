defmodule NostrSpamFighter.Scanner.AddressValidatorTest do
  use ExUnit.Case, async: true
  alias NostrSpamFighter.Scanner.AddressValidator

  test "rejects loopback and RFC1918" do
    refute AddressValidator.public_ip?({127, 0, 0, 1})
    refute AddressValidator.public_ip?({10, 0, 0, 1})
    refute AddressValidator.public_ip?({192, 168, 1, 1})
    refute AddressValidator.public_ip?({172, 16, 0, 1})
    refute AddressValidator.public_ip?({169, 254, 1, 1})
    refute AddressValidator.public_ip?({169, 254, 169, 254})
  end

  test "rejects IPv6 loopback, ULA, and link-local" do
    refute AddressValidator.public_ip?({0, 0, 0, 0, 0, 0, 0, 1})
    refute AddressValidator.public_ip?({0xFC00, 0, 0, 0, 0, 0, 0, 1})
    refute AddressValidator.public_ip?({0xFE80, 0, 0, 0, 0, 0, 0, 1})
  end

  test "rejects IPv4-mapped loopback" do
    refute AddressValidator.public_ip?({0, 0, 0, 0, 0, 65_535, 0x7F00, 1})
  end

  test "accepts public IPv4" do
    assert AddressValidator.public_ip?({1, 1, 1, 1})
  end

  test "rejects localhost url before connect" do
    assert {:error, :blocked_address} = AddressValidator.validate_url("http://127.0.0.1/")
    assert {:error, :blocked_address} = AddressValidator.validate_url("http://localhost/")
  end

  test "rejects unsupported schemes" do
    assert {:error, :unsupported_scheme} = AddressValidator.validate_url("gopher://example.com/")
  end
end
