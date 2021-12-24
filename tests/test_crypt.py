import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from utils import Signer, uint, str_to_felt, MAX_UINT256

signer = Signer(123456789987654321)
underlying_addr = 101

@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()

@pytest.fixture(scope='module')
async def initialize():
    starknet = await Starknet.empty()
    owner = await starknet.deploy(
        "contracts/utils/Account.cairo",
        constructor_calldata=[signer.public_key]
    )

    crypt = await starknet.deploy(
        "contracts/Crypt.cairo",
        constructor_calldata=[
            underlying_addr, # underlying
        ]
    )
    return starknet, crypt, owner

@pytest.mark.asyncio
async def test_constructor(initialize):
    _, crypt, _ = initialize

    # Validate `underlying` set properly
    expected = await crypt.underlying().call()
    assert expected.result.underlying == underlying_addr


@pytest.mark.asyncio
async def test_set_name(initialize):
    _, crypt, _ = initialize

    # Validate `underlying` set properly
    expected = await crypt.underlying().call()
    assert expected.result.underlying == underlying_addr

