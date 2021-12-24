import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from utils import Signer, uint, str_to_felt, MAX_UINT256

signer = Signer(123456789987654321)
owner_addr = 101

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

    factory = await starknet.deploy(
        "contracts/CryptFactory.cairo",
        constructor_calldata=[
            owner_addr, # owner
            1 # initialized
        ]
    )

    return starknet, factory, owner


@pytest.mark.asyncio
async def test_constructor(initialize):
    _, factory, _ = initialize

    # Validate `owner` set properly
    expected = await factory.owner().call()
    assert expected.result.owner == owner_addr

    # Validate `initialized` set properly
    expected = await factory.initialized().call()
    assert expected.result.initialized == 1

