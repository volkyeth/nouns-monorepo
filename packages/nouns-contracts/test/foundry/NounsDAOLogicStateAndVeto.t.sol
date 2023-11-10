// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { INounsDAOShared } from './helpers/INounsDAOShared.sol';
import { NounsDAOLogicV2 } from '../../contracts/governance/NounsDAOLogicV2.sol';
import { NounsDAOLogicV3 } from '../../contracts/governance/NounsDAOLogicV3.sol';
import { NounsDAOProxy } from '../../contracts/governance/NounsDAOProxy.sol';
import { NounsDAOProxyV2 } from '../../contracts/governance/NounsDAOProxyV2.sol';
import { NounsDAOStorageV2, NounsDAOStorageV3 } from '../../contracts/governance/NounsDAOInterfaces.sol';
import { NounsDescriptorV2 } from '../../contracts/NounsDescriptorV2.sol';
import { NounsToken } from '../../contracts/NounsToken.sol';
import { NounsSeeder } from '../../contracts/NounsSeeder.sol';
import { IProxyRegistry } from '../../contracts/external/opensea/IProxyRegistry.sol';
import { NounsDAOExecutor } from '../../contracts/governance/NounsDAOExecutor.sol';
import { NounsDAOLogicSharedBaseTest } from './helpers/NounsDAOLogicSharedBase.t.sol';

abstract contract NounsDAOLogicStateBaseTest is NounsDAOLogicSharedBaseTest {
    function setUp() public override {
        super.setUp();

        mint(proposer, 1);

        vm.roll(block.number + 1);
    }

    function testRevertsGivenProposalIdThatDoesntExist() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.expectRevert('NounsDAO::state: invalid proposal id');
        daoProxy.state(proposalId + 1);
    }

    function testPendingGivenProposalJustCreated() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        uint256 state = uint256(NounsDAOLogicV3(payable(address(daoProxy))).state(proposalId));

        if (daoVersion() < 3) {
            assertEq(state, uint256(NounsDAOStorageV3.ProposalState.Pending));
        } else {
            assertEq(state, uint256(NounsDAOStorageV3.ProposalState.Updatable));
        }
    }

    function testActiveGivenProposalPastVotingDelay() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.roll(block.number + daoProxy.votingDelay() + 1);
        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Active);
    }

    function testCanceledGivenCanceledProposal() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.prank(proposer);
        daoProxy.cancel(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Canceled);
    }

    function testDefeatedByRunningOutOfTime() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.roll(block.number + daoProxy.votingDelay() + daoProxy.votingPeriod() + 1);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Defeated);
    }

    function testDefeatedByVotingAgainst() public {
        address forVoter = utils.getNextUserAddress();
        address againstVoter = utils.getNextUserAddress();
        mint(forVoter, 3);
        mint(againstVoter, 3);

        uint256 proposalId = propose(address(0x1234), 100, '', '');
        startVotingPeriod();
        vote(forVoter, proposalId, 1);
        vote(againstVoter, proposalId, 0);
        endVotingPeriod();

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Defeated);
    }

    function testSucceeded() public {
        address forVoter = utils.getNextUserAddress();
        address againstVoter = utils.getNextUserAddress();
        mint(forVoter, 4);
        mint(againstVoter, 3);

        uint256 proposalId = propose(address(0x1234), 100, '', '');
        startVotingPeriod();
        vote(forVoter, proposalId, 1);
        vote(againstVoter, proposalId, 0);
        endVotingPeriod();

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Succeeded);
    }

    function testQueueRevertsGivenDefeatedProposal() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.roll(block.number + daoProxy.votingDelay() + daoProxy.votingPeriod() + 1);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Defeated);

        vm.expectRevert('NounsDAO::queue: proposal can only be queued if it is succeeded');
        daoProxy.queue(proposalId);
    }

    function testQueueRevertsGivenCanceledProposal() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.prank(proposer);
        daoProxy.cancel(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Canceled);

        vm.expectRevert('NounsDAO::queue: proposal can only be queued if it is succeeded');
        daoProxy.queue(proposalId);
    }

    function testQueued() public {
        address forVoter = utils.getNextUserAddress();
        address againstVoter = utils.getNextUserAddress();
        mint(forVoter, 4);
        mint(againstVoter, 3);

        uint256 proposalId = propose(address(0x1234), 100, '', '');
        startVotingPeriod();
        vote(forVoter, proposalId, 1);
        vote(againstVoter, proposalId, 0);
        endVotingPeriod();

        // anyone can queue
        daoProxy.queue(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Queued);
    }

    function testExpired() public {
        address forVoter = utils.getNextUserAddress();
        address againstVoter = utils.getNextUserAddress();
        mint(forVoter, 4);
        mint(againstVoter, 3);

        uint256 proposalId = propose(address(0x1234), 100, '', '');
        startVotingPeriod();
        vote(forVoter, proposalId, 1);
        vote(againstVoter, proposalId, 0);
        endVotingPeriod();
        daoProxy.queue(proposalId);
        vm.warp(block.timestamp + timelock.delay() + timelock.GRACE_PERIOD() + 1);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Expired);
    }

    function testExecutedOnlyAfterQueued() public {
        address forVoter = utils.getNextUserAddress();
        mint(forVoter, 4);

        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.expectRevert('NounsDAO::execute: proposal can only be executed if it is queued');
        daoProxy.execute(proposalId);

        startVotingPeriod();
        vote(forVoter, proposalId, 1);
        vm.expectRevert('NounsDAO::execute: proposal can only be executed if it is queued');
        daoProxy.execute(proposalId);

        endVotingPeriod();
        vm.expectRevert('NounsDAO::execute: proposal can only be executed if it is queued');
        daoProxy.execute(proposalId);

        daoProxy.queue(proposalId);
        vm.expectRevert("NounsDAOExecutor::executeTransaction: Transaction hasn't surpassed time lock.");
        daoProxy.execute(proposalId);

        vm.warp(block.timestamp + timelock.delay() + 1);
        vm.deal(address(timelock), 100);
        daoProxy.execute(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Executed);

        vm.warp(block.timestamp + timelock.delay() + timelock.GRACE_PERIOD() + 1);
        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Executed);
    }
}

contract NounsDAOLogicV1ForkStateTest is NounsDAOLogicStateBaseTest {
    function daoVersion() internal pure override returns (uint256) {
        return 1;
    }

    function deployDAOProxy(
        address,
        address,
        address
    ) internal override returns (INounsDAOShared) {
        return INounsDAOShared(address(deployForkDAOProxy()));
    }
}

contract NounsDAOLogicV3StateTest is NounsDAOLogicStateBaseTest {
    function deployDAOProxy(
        address timelock,
        address nounsToken,
        address vetoer
    ) internal override returns (INounsDAOShared) {
        return _createDAOV3Proxy(timelock, nounsToken, vetoer);
    }

    function daoVersion() internal pure override returns (uint256) {
        return 3;
    }
}

abstract contract NounsDAOLogicVetoingBaseTest is NounsDAOLogicSharedBaseTest {
    function setUp() public override {
        super.setUp();

        mint(proposer, 1);

        vm.roll(block.number + 1);
    }

    function testVetoerSetAsExpected() public {
        assertEq(daoProxy.vetoer(), vetoer);
    }

    function test_burnVetoPower_revertsForNonVetoer() public {
        vm.expectRevert('NounsDAO::_burnVetoPower: vetoer only');
        daoProxy._burnVetoPower();
    }

    function test_burnVetoPower_worksForVetoer() public {
        assertEq(daoProxy.vetoer(), vetoer);

        vm.prank(vetoer);
        daoProxy._burnVetoPower();

        assertEq(daoProxy.vetoer(), address(0));
    }

    function test_veto_revertsForNonVetoer() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');

        if (daoVersion() == 1) {
            vm.expectRevert('NounsDAO::veto: only vetoer');
        } else {
            vm.expectRevert(NounsDAOLogicV2.VetoerOnly.selector);
        }
        daoProxy.veto(proposalId);
    }

    function test_veto_revertsWhenVetoerIsBurned() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.startPrank(vetoer);
        daoProxy._burnVetoPower();

        if (daoVersion() == 1) {
            vm.expectRevert('NounsDAO::veto: veto power burned');
        } else {
            vm.expectRevert(NounsDAOLogicV2.VetoerBurned.selector);
        }
        daoProxy.veto(proposalId);

        vm.stopPrank();
    }

    function test_veto_worksForPropStatePending() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        // Need to roll one block because in V3 on the proposal creation block the state is Updatable
        vm.roll(block.number + 1);
        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Pending);

        vm.prank(vetoer);
        daoProxy.veto(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Vetoed);
    }

    function test_veto_worksForPropStateActive() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.roll(block.number + daoProxy.votingDelay() + 1);
        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Active);

        vm.prank(vetoer);
        daoProxy.veto(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Vetoed);
    }

    function test_veto_worksForPropStateCanceled() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.prank(proposer);
        daoProxy.cancel(proposalId);
        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Canceled);

        vm.prank(vetoer);
        daoProxy.veto(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Vetoed);
    }

    function test_veto_worksForPropStateDefeated() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.roll(block.number + daoProxy.votingDelay() + 1);
        vm.prank(proposer);
        daoProxy.castVote(proposalId, 0);
        vm.roll(block.number + daoProxy.votingPeriod() + 1);
        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Defeated);

        vm.prank(vetoer);
        daoProxy.veto(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Vetoed);
    }

    function test_veto_worksForPropStateSucceeded() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.roll(block.number + daoProxy.votingDelay() + 1);
        vm.prank(proposer);
        daoProxy.castVote(proposalId, 1);
        vm.roll(block.number + daoProxy.votingPeriod() + 1);
        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Succeeded);

        vm.prank(vetoer);
        daoProxy.veto(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Vetoed);
    }

    function test_veto_worksForPropStateQueued() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.roll(block.number + daoProxy.votingDelay() + 1);
        vm.prank(proposer);
        daoProxy.castVote(proposalId, 1);
        vm.roll(block.number + daoProxy.votingPeriod() + 1);
        daoProxy.queue(proposalId);
        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Queued);

        vm.prank(vetoer);
        daoProxy.veto(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Vetoed);
    }

    function test_veto_worksForPropStateExpired() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.roll(block.number + daoProxy.votingDelay() + 1);
        vm.prank(proposer);
        daoProxy.castVote(proposalId, 1);
        vm.roll(block.number + daoProxy.votingPeriod() + 1);
        daoProxy.queue(proposalId);
        vm.warp(block.timestamp + timelock.delay() + timelock.GRACE_PERIOD() + 1);
        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Expired);

        vm.prank(vetoer);
        daoProxy.veto(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Vetoed);
    }

    function test_veto_revertsForPropStateExecuted() public {
        vm.deal(address(timelock), 100);
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.roll(block.number + daoProxy.votingDelay() + 1);
        vm.prank(proposer);
        daoProxy.castVote(proposalId, 1);
        vm.roll(block.number + daoProxy.votingPeriod() + 1);
        daoProxy.queue(proposalId);
        vm.warp(block.timestamp + timelock.delay() + 1);
        daoProxy.execute(proposalId);
        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Executed);

        vm.prank(vetoer);
        if (daoVersion() == 1) {
            vm.expectRevert('NounsDAO::veto: cannot veto executed proposal');
        } else {
            vm.expectRevert(NounsDAOLogicV2.CantVetoExecutedProposal.selector);
        }
        daoProxy.veto(proposalId);
    }

    function test_veto_worksForPropStateVetoed() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.prank(vetoer);
        daoProxy.veto(proposalId);
        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Vetoed);

        vm.prank(vetoer);
        daoProxy.veto(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOStorageV3.ProposalState.Vetoed);
    }
}

contract NounsDAOLogicV3VetoingTest is NounsDAOLogicVetoingBaseTest {
    event NewPendingVetoer(address oldPendingVetoer, address newPendingVetoer);
    event NewVetoer(address oldVetoer, address newVetoer);

    function test_veto_worksForPropStateUpdatable() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        NounsDAOLogicV3 daoAsV3 = NounsDAOLogicV3(payable(address(daoProxy)));

        assertTrue(daoAsV3.state(proposalId) == NounsDAOStorageV3.ProposalState.Updatable);

        vm.prank(vetoer);
        daoAsV3.veto(proposalId);

        assertTrue(daoAsV3.state(proposalId) == NounsDAOStorageV3.ProposalState.Vetoed);
    }

    function test_setPendingVetoer_failsIfNotCurrentVetoer() public {
        vm.expectRevert(NounsDAOLogicV2.VetoerOnly.selector);
        daoProxyAsV2()._setPendingVetoer(address(0x1234));
    }

    function test_setPendingVetoer_updatePendingVetoer() public {
        assertEq(daoProxyAsV2().pendingVetoer(), address(0));

        address pendingVetoer = address(0x3333);

        vm.prank(vetoer);
        vm.expectEmit(true, true, true, true);
        emit NewPendingVetoer(address(0), pendingVetoer);
        daoProxyAsV2()._setPendingVetoer(pendingVetoer);

        assertEq(daoProxyAsV2().pendingVetoer(), pendingVetoer);
    }

    function test_onlyPendingVetoerCanAcceptNewVetoer() public {
        address pendingVetoer = address(0x3333);

        vm.prank(vetoer);
        daoProxyAsV2()._setPendingVetoer(pendingVetoer);

        vm.expectRevert(NounsDAOLogicV2.PendingVetoerOnly.selector);
        daoProxyAsV2()._acceptVetoer();

        vm.prank(pendingVetoer);
        vm.expectEmit(true, true, true, true);
        emit NewVetoer(vetoer, pendingVetoer);
        daoProxyAsV2()._acceptVetoer();

        assertEq(daoProxy.vetoer(), pendingVetoer);
        assertEq(daoProxyAsV2().pendingVetoer(), address(0x0));
    }

    function test_burnVetoPower_failsIfNotVetoer() public {
        vm.expectRevert('NounsDAO::_burnVetoPower: vetoer only');
        daoProxy._burnVetoPower();
    }

    function test_burnVetoPower_setsVetoerToZero() public {
        vm.prank(vetoer);
        vm.expectEmit(true, true, true, true);
        emit NewVetoer(vetoer, address(0));
        daoProxy._burnVetoPower();

        assertEq(daoProxy.vetoer(), address(0));
    }

    function test_burnVetoPower_setsPendingVetoerToZero() public {
        address pendingVetoer = address(0x3333);

        vm.prank(vetoer);
        daoProxyAsV2()._setPendingVetoer(pendingVetoer);

        vm.prank(vetoer);
        vm.expectEmit(true, true, true, true);
        emit NewPendingVetoer(pendingVetoer, address(0));
        daoProxy._burnVetoPower();

        vm.prank(pendingVetoer);
        vm.expectRevert(NounsDAOLogicV2.PendingVetoerOnly.selector);
        daoProxyAsV2()._acceptVetoer();

        assertEq(daoProxyAsV2().pendingVetoer(), address(0));
    }

    function deployDAOProxy(
        address timelock,
        address nounsToken,
        address vetoer
    ) internal override returns (INounsDAOShared) {
        return _createDAOV3Proxy(timelock, nounsToken, vetoer);
    }

    function daoVersion() internal pure override returns (uint256) {
        return 3;
    }
}
