// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-contracts-5.6.1/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin-contracts-5.6.1/utils/structs/EnumerableSet.sol";
import {Time} from "@openzeppelin-contracts-5.6.1/utils/types/Time.sol";

import {IDeliberate} from "./interfaces/IDeliberate.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";
import {Argument} from "./libs/Argument.sol";
import {Bounty} from "./libs/Bounty.sol";
import {Debate} from "./libs/Debate.sol";
import {Parameters} from "./libs/Parameters.sol";
import {Phase} from "./libs/Phase.sol";
import {User} from "./libs/User.sol";
import {Utils} from "./libs/Utils.sol";

/// @title Deliberate
/// @author Michael Heuer
/// @notice A voting module for deliberative decision-making using argument trees. The contract is deployed once,
/// has no owner, and is not upgradeable.
contract Deliberate is IDeliberate {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;
    using Utils for uint32;
    using Utils for int64;
    using Debate for Debate.Data;

    /// @notice The counter tracking the number of created debates.
    uint256 internal _debatesCounter;

    /// @notice The debates by their ID.
    mapping(uint256 debateId => Debate.Data debate) internal _debates;

    /// @notice The users by debate ID and account.
    mapping(uint256 debateId => mapping(address account => User.Data user)) internal _users;

    /// @notice The phase data by debate ID.
    mapping(uint256 debateId => Phase.Data phase) internal _phases;

    /// @notice The bounties by debate ID.
    mapping(uint256 debateId => Bounty.Data bounty) internal _bounties;

    /// @notice Thrown if a debate is uninitialized.
    /// @param debateId The ID of the debate.
    error DebateUninitialized(uint256 debateId);

    /// @notice Thrown if the phase of a debate is invalid.
    /// @param expected The expected debate phase.
    /// @param actual The actual debate phase.
    error PhaseInvalid(Phase.Status expected, Phase.Status actual);

    /// @notice Thrown if the phase of a debate is past the latest permitted phase.
    /// @param limit The latest permitted debate phase.
    /// @param actual The actual debate phase.
    error PhaseExceeded(Phase.Status limit, Phase.Status actual);

    /// @notice Thrown if an argument is required to be final (its editing window elapsed) but is not.
    /// @param argumentId The ID of the argument.
    error ArgumentNotFinal(uint16 argumentId);

    /// @notice Thrown if an argument is required to be an editable draft (inside its editing window) but is not.
    /// @param argumentId The ID of the argument.
    error ArgumentNotDraft(uint16 argumentId);

    /// @notice Thrown if the role of a user is invalid.
    /// @param expected The expected role.
    /// @param actual The actual role.
    error RoleInvalid(User.Role expected, User.Role actual);

    /// @notice Thrown if an address is invalid.
    /// @param expected The expected address.
    /// @param actual The actual address.
    error AddressInvalid(address expected, address actual);

    /// @notice Thrown if the identity proof of an account is invalid.
    error IdentityProofInvalid();

    /// @notice Thrown if the time is out of bounds.
    /// @param limit The limit time as a unix timestamp.
    /// @param actual The actual time as a unix timestamp.
    error TimeOutOfBounds(uint48 limit, uint48 actual);

    /// @notice Thrown if a debate is created with a zero locking duration, which would finalize every
    /// argument at creation, leaving nothing editable or movable.
    error LockingDurationZero();

    /// @notice Thrown if a debate is created with a phase too short relative to its locking duration.
    /// @param minimum The locking duration the phase must fit (the editing phase must exceed it).
    /// @param actual The duration passed.
    error DurationTooShort(uint48 minimum, uint48 actual);

    /// @notice Thrown if a debate is created with a market fee above the permitted maximum.
    /// @param limit The highest permitted fee percentage.
    /// @param actual The fee percentage passed.
    error FeePercentageExceeded(uint8 limit, uint8 actual);

    /// @notice Thrown if a thesis or argument is created or altered with empty content.
    error ContentEmpty();

    /// @notice Thrown if a thesis or argument is created or altered with content above the permitted length.
    /// @param limit The longest permitted content, in bytes.
    /// @param actual The length of the content passed, in bytes.
    error ContentTooLong(uint256 limit, uint256 actual);

    /// @notice Thrown if initial approval value is out of bounds.
    /// @param limit The limit initial approval value.
    /// @param actual The actual initial approval value.
    error InitialApprovalOutOfBounds(uint8 limit, uint8 actual);

    /// @notice Thrown if the vote token balance is too low.
    /// @param required The required vote tokens.
    /// @param actual The actual vote token balance.
    error InsufficientVoteTokens(uint32 required, uint32 actual);

    /// @notice Thrown if the chosen argument deposit is below the permitted minimum.
    /// @param minimum The minimum permitted deposit.
    /// @param actual The actual deposit chosen.
    error DepositBelowMinimum(uint32 minimum, uint32 actual);

    /// @notice Thrown if a debate has reached its maximum number of arguments.
    /// @param limit The maximum number of arguments per debate.
    error ArgumentLimitReached(uint16 limit);

    /// @notice Thrown if the thesis (argument 0), which has no market, is staked on.
    error ThesisHasNoMarket();

    /// @notice Thrown if the childs of the argument are not tallied.
    /// @param untalliedChilds The number of untallied childs.
    error ChildsUntallied(uint16 untalliedChilds);

    /// @notice Thrown if a debate is created with a bounty amount but no bounty token.
    error BountyTokenZero();

    /// @notice Thrown if a bounty action targets a debate that has no bounty token.
    error BountyMissing();

    /// @notice Thrown if a bounty is funded with a zero amount.
    error BountyAmountZero();

    /// @notice Thrown if a bounty claim arrives after the claim window has closed.
    /// @param closedAt The time the claim window closed.
    error ClaimWindowClosed(uint48 closedAt);

    /// @notice Thrown if the sweep is attempted while the claim window is still open.
    /// @param closesAt The time the claim window closes.
    error ClaimWindowOpen(uint48 closesAt);

    /// @notice Thrown if a participant tries to claim a bounty share twice - claims are one-shot.
    error BountyAlreadyClaimed();

    /// @notice Thrown if a participant without excess over the initial grant tries to claim.
    /// @param tokens The participant's vote token balance.
    error BountyNotWon(uint32 tokens);

    /// @notice Thrown if the bounty remainder has already been swept.
    error BountyAlreadySwept();

    /// @notice A modifier to restrict functions to only be called if the debate is in a certain phase.
    /// @param debateId The ID of the debate.
    /// @param phase The phase of the debate required.
    modifier onlyPhase(uint256 debateId, Phase.Status phase) {
        _onlyPhase({debateId: debateId, phase: phase});
        _;
    }

    /// @notice A modifier to restrict functions to only act on a final argument: one whose editing window
    /// has elapsed (or the permanently-final thesis).
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    modifier onlyFinalArgument(uint256 debateId, uint16 argumentId) {
        _onlyFinalArgument({debateId: debateId, argumentId: argumentId});
        _;
    }

    /// @notice A modifier to restrict functions to only act on a draft argument: one still inside its editing
    /// window, hence editable and movable but not yet tradeable.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    modifier onlyDraftArgument(uint256 debateId, uint16 argumentId) {
        _onlyDraftArgument({debateId: debateId, argumentId: argumentId});
        _;
    }

    /// @notice A modifier to restrict functions to only be called by the creator of an argument.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    modifier onlyCreator(uint256 debateId, uint16 argumentId) {
        _onlyCreator({debateId: debateId, argumentId: argumentId});
        _;
    }

    /// @notice A modifier to restrict functions to be only called by accounts holding a certain role.
    /// @param debateId The ID of the debate.
    /// @param role The role required.
    modifier onlyRole(uint256 debateId, User.Role role) {
        _onlyRole({debateId: debateId, role: role});
        _;
    }

    /// @inheritdoc IDeliberate
    function createDebate(
        string calldata content,
        uint48 lockingDuration,
        uint48 editingDuration,
        uint48 ratingDuration,
        uint8 feePercentage,
        IIdentityRegistry identityRegistry,
        IERC20 bountyToken,
        uint256 bountyAmount
    ) external override returns (uint256 debateId) {
        _checkContent(content);

        // A zero locking duration would finalize every argument at creation, leaving nothing editable or movable.
        if (lockingDuration == 0) {
            revert LockingDurationZero();
        }
        // The editing phase must exceed the locking duration (strictly - the + 1 keeps the comparison strict),
        // so arguments can lock in and be replied to: nesting needs final parents.
        if (editingDuration < lockingDuration + 1) {
            revert DurationTooShort({minimum: lockingDuration, actual: editingDuration});
        }
        // The rating phase must fit at least one locking window, so an argument added in the editing phase's
        // last moment is final by the time the tally runs.
        if (ratingDuration < lockingDuration) {
            revert DurationTooShort({minimum: lockingDuration, actual: ratingDuration});
        }
        // A fee of 100% or more would let a stake degenerate into a pure fee transfer moving no market.
        if (feePercentage > Parameters._MAX_FEE_PERCENTAGE) {
            revert FeePercentageExceeded({limit: Parameters._MAX_FEE_PERCENTAGE, actual: feePercentage});
        }

        debateId = _debatesCounter;
        _debatesCounter++;

        // Create the root Argument
        Debate.Data storage newDebate = _debates[debateId];
        Argument.Data storage rootArgument = newDebate.arguments[0];

        // Create the root argument of the tree - the thesis. Setting its finalization time to creation makes it
        // final from the start (finality is derived from the clock, not stored), so it can immediately parent.
        // Its text is published by the event below and kept nowhere.
        rootArgument.creator = msg.sender;
        rootArgument.finalizationTime = Time.timestamp();

        // Store the phase-related data. The phase itself is not stored: Editing, Rating, and Tallying are
        // derived from these time gates on read, and only the terminal Finished phase is later latched by the tally.
        Phase.Data storage phaseData = _phases[debateId];
        phaseData.lockingDuration = lockingDuration;
        phaseData.editingEndTime = Time.timestamp() + editingDuration;
        phaseData.ratingEndTime = phaseData.editingEndTime + ratingDuration;

        newDebate.feePercentage = feePercentage;

        // Who may join, chosen per debate: the zero address leaves it open to everyone, any other address is
        // asked `isRegistered` on each join. One registry serves any number of debates, so a creator curating a
        // membership - their own allowlist, or a Circles group they already maintain - reuses it by address.
        newDebate.identityRegistry = identityRegistry;

        // increment counters
        newDebate.incrementArgumentCounter();

        emit DebateCreated({
            debateId: debateId,
            creator: msg.sender,
            content: content,
            lockingDuration: lockingDuration,
            editingEndTime: phaseData.editingEndTime,
            ratingEndTime: phaseData.ratingEndTime,
            feePercentage: feePercentage,
            identityRegistry: identityRegistry
        });

        // Attach the optional bounty: the token is fixed for the debate's lifetime, the amount may be
        // zero to leave the funding to top-ups.
        if (address(bountyToken) != address(0)) {
            _bounties[debateId].token = bountyToken;
            if (bountyAmount > 0) {
                _fundBounty(debateId, bountyAmount);
            }
        } else if (bountyAmount > 0) {
            revert BountyTokenZero();
        }
    }

    /// @inheritdoc IDeliberate
    function join(uint256 debateId) external override onlyRole(debateId, User.Role.Unassigned) {
        // Joining is only possible while participating is: during the editing and rating phases.
        Phase.Status currentPhase = _phaseOf(_phases[debateId]);
        if (currentPhase == Phase.Status.Uninitialized) {
            revert DebateUninitialized({debateId: debateId});
        }
        if (currentPhase > Phase.Status.Rating) {
            revert PhaseExceeded({limit: Phase.Status.Rating, actual: currentPhase});
        }

        // An open debate has no registry to ask; every other mode is one `isRegistered` call away, which is
        // what lets a personhood proof, a curated allowlist and a Circles group be the same thing here.
        IIdentityRegistry registry = _debates[debateId].identityRegistry;
        if (address(registry) != address(0) && !registry.isRegistered(msg.sender)) {
            revert IdentityProofInvalid();
        }

        User.Data storage user = _users[debateId][msg.sender];

        user.role = User.Role.Participant;
        user.tokens = Parameters.INITIAL_TOKENS;

        // The participant count is the `N` in the bounty payout denominator (and a quorum input for
        // outcome consumers); joining closes with the rating phase, so it is fixed once claims open.
        _debates[debateId].incrementParticipantCounter();

        emit Joined({debateId: debateId, account: msg.sender, tokens: Parameters.INITIAL_TOKENS});
    }

    /// @inheritdoc IDeliberate
    function fundBounty(uint256 debateId, uint256 amount) external override {
        if (address(_bounties[debateId].token) == address(0)) {
            revert BountyMissing();
        }
        if (amount == 0) {
            revert BountyAmountZero();
        }
        // Top-ups close once the debate is finished: the pool must be constant while claims divide it.
        if (_phases[debateId].finished) {
            revert PhaseExceeded({limit: Phase.Status.Tallying, actual: Phase.Status.Finished});
        }

        _fundBounty(debateId, amount);
    }

    /// @inheritdoc IDeliberate
    /// @dev The new parent must be final, mirroring `createArgument`. This also rules out cycles: children only ever
    /// attach beneath final arguments while only drafts (still inside their editing window) can move, so a draft is
    /// always childless - its subtree is itself alone - and it is not final.
    function moveArgument(uint256 debateId, uint16 argumentId, uint16 newParentArgumentId, uint8 initialApproval)
        external
        override
        onlyPhase(debateId, Phase.Status.Editing)
        onlyCreator(debateId, argumentId)
        onlyDraftArgument(debateId, argumentId)
        onlyFinalArgument(debateId, newParentArgumentId)
    {
        _checkInitialApproval(initialApproval);

        Debate.Data storage debate = _debates[debateId];
        Argument.Data storage movedArgument = debate.arguments[argumentId];

        // change old parent's argument state
        uint16 oldParentArgumentId = movedArgument.parentArgumentId;
        _updateParentAfterChildRemoval({debateId: debateId, parentArgumentId: oldParentArgumentId});

        // change argument state
        movedArgument.parentArgumentId = newParentArgumentId;

        // Re-seed the market at the new approval. Only a draft can move and drafts cannot be
        // staked on, so the reserves are still the pristine deposit split - re-splitting the
        // argument's own deposit (its unchanged votes) is lossless, whatever deposit the
        // creator chose.
        (movedArgument.pro, movedArgument.con) = movedArgument.votes.split(100 - initialApproval, initialApproval);

        // change new parent argument state
        _updateParentAfterChildAttachment({debateId: debateId, parentArgumentId: newParentArgumentId});

        emit ArgumentMoved({
            debateId: debateId,
            argumentId: argumentId,
            newParentArgumentId: newParentArgumentId,
            oldParentArgumentId: oldParentArgumentId,
            pro: movedArgument.pro,
            con: movedArgument.con
        });
    }

    /// @inheritdoc IDeliberate
    function alterArgument(uint256 debateId, uint16 argumentId, string calldata content)
        external
        override
        onlyPhase(debateId, Phase.Status.Editing)
        onlyCreator(debateId, argumentId)
        onlyDraftArgument(debateId, argumentId)
    {
        _checkContent(content);

        uint48 newFinalizationTime = Time.timestamp() + _phases[debateId].lockingDuration;

        if (newFinalizationTime > _phases[debateId].editingEndTime) {
            revert TimeOutOfBounds({limit: _phases[debateId].editingEndTime, actual: newFinalizationTime});
        }

        Argument.Data storage alteredArgument = _debates[debateId].arguments[argumentId];
        // Only the restarted window is state; the new text is published by the event alone.
        alteredArgument.finalizationTime = newFinalizationTime;

        emit ArgumentAltered({
            debateId: debateId, argumentId: argumentId, content: content, finalizationTime: newFinalizationTime
        });
    }

    /// @inheritdoc IDeliberate
    function stakePro(uint256 debateId, uint16 argumentId, uint32 voteTokenAmount)
        external
        override
        onlyPhase(debateId, Phase.Status.Rating)
        onlyFinalArgument(debateId, argumentId)
    {
        _stake({debateId: debateId, argumentId: argumentId, isPro: true, voteTokenAmount: voteTokenAmount});
    }

    /// @inheritdoc IDeliberate
    function stakeCon(uint256 debateId, uint16 argumentId, uint32 voteTokenAmount)
        external
        override
        onlyPhase(debateId, Phase.Status.Rating)
        onlyFinalArgument(debateId, argumentId)
    {
        _stake({debateId: debateId, argumentId: argumentId, isPro: false, voteTokenAmount: voteTokenAmount});
    }

    /// @inheritdoc IDeliberate
    function tallyTree(uint256 debateId) external override onlyPhase(debateId, Phase.Status.Tallying) {
        uint256[] memory leafArgumentIds = _debates[debateId].leafArgumentIds.values();

        uint256 arrayLength = leafArgumentIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            _tallyNode(debateId, SafeCast.toUint16(leafArgumentIds[i]));
        }

        // Latch the terminal phase: the tally is the single transaction that finishes a debate, no separate
        // poke. The finish time anchors the bounty claim window.
        _phases[debateId].finished = true;
        _phases[debateId].finishTime = Time.timestamp();

        // The denominator is positive, so the numerator's sign is the aggregate's.
        emit DebateFinished({debateId: debateId, approved: _debates[debateId].arguments[0].descendantsNumerator > 0});
    }

    /// @inheritdoc IDeliberate
    function redeemArgumentShares(uint256 debateId, uint16 argumentId, address account)
        external
        override
        onlyPhase(debateId, Phase.Status.Finished)
    {
        _redeemArgumentShares({debateId: debateId, argumentId: argumentId, account: account});
    }

    /// @inheritdoc IDeliberate
    function redeemArgumentSharesBatch(uint256 debateId, uint16[] calldata argumentIds, address account)
        external
        override
        onlyPhase(debateId, Phase.Status.Finished)
    {
        uint256 arrayLength = argumentIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            _redeemArgumentShares({debateId: debateId, argumentId: argumentIds[i], account: account});
        }
    }

    /// @inheritdoc IDeliberate
    function claimFees(uint256 debateId, uint16 argumentId)
        external
        override
        onlyPhase(debateId, Phase.Status.Finished)
    {
        _claimFees({debateId: debateId, argumentId: argumentId});
    }

    /// @inheritdoc IDeliberate
    function claimBounty(uint256 debateId, uint16[] calldata argumentIds)
        external
        override
        onlyPhase(debateId, Phase.Status.Finished)
    {
        Bounty.Data storage bountyData = _bounties[debateId];
        if (address(bountyData.token) == address(0)) {
            revert BountyMissing();
        }
        uint48 closesAt = _phases[debateId].finishTime + Parameters.CLAIM_WINDOW;
        if (Time.timestamp() > closesAt) {
            revert ClaimWindowClosed({closedAt: closesAt});
        }

        User.Data storage user = _users[debateId][msg.sender];
        if (user.bountyClaimed) {
            revert BountyAlreadyClaimed();
        }

        // Settle-and-claim: redeem the given share positions and claim their accrued creator fees first,
        // so the excess below is the caller's full result - claiming early (claims are one-shot) cannot
        // silently forfeit unredeemed positions.
        uint256 arrayLength = argumentIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            _redeemArgumentShares({debateId: debateId, argumentId: argumentIds[i], account: msg.sender});
            _claimFees({debateId: debateId, argumentId: argumentIds[i]});
        }

        uint32 tokens = user.tokens;
        if (tokens < Parameters.INITIAL_TOKENS + 1) {
            revert BountyNotWon({tokens: tokens});
        }
        uint32 excess = tokens - Parameters.INITIAL_TOKENS;

        // The fixed denominator (initial supply): a collusion ring only ever reaches its headcount share.
        uint256 amount =
            (bountyData.pool * excess) / (uint256(Parameters.INITIAL_TOKENS) * _debates[debateId].participantsCount);

        user.bountyClaimed = true;
        bountyData.claimed += amount;
        if (amount > 0) {
            bountyData.token.safeTransfer(msg.sender, amount);
        }

        emit BountyClaimed({debateId: debateId, account: msg.sender, excess: excess, amount: amount});
    }

    /// @inheritdoc IDeliberate
    function sweepBounty(uint256 debateId) external override onlyPhase(debateId, Phase.Status.Finished) {
        Bounty.Data storage bountyData = _bounties[debateId];
        if (address(bountyData.token) == address(0)) {
            revert BountyMissing();
        }

        address creator = _debates[debateId].arguments[0].creator;
        if (msg.sender != creator) {
            revert AddressInvalid({expected: creator, actual: msg.sender});
        }
        uint48 closesAt = _phases[debateId].finishTime + Parameters.CLAIM_WINDOW;
        if (Time.timestamp() < closesAt + 1) {
            revert ClaimWindowOpen({closesAt: closesAt});
        }
        if (bountyData.swept) {
            revert BountyAlreadySwept();
        }

        uint256 remainder = bountyData.pool - bountyData.claimed;
        bountyData.swept = true;
        if (remainder > 0) {
            bountyData.token.safeTransfer(creator, remainder);
        }

        emit BountySwept({debateId: debateId, creator: creator, amount: remainder});
    }

    /// @inheritdoc IDeliberate
    function getArgument(uint256 debateId, uint16 argumentId)
        external
        view
        override
        returns (Argument.Data memory argument)
    {
        return _debates[debateId].arguments[argumentId];
    }

    /// @inheritdoc IDeliberate
    function getLeafArgumentIds(uint256 debateId) external view override returns (uint16[] memory leafArgumentIds) {
        uint256[] memory ids = _debates[debateId].leafArgumentIds.values();

        uint256 arrayLength = ids.length;
        leafArgumentIds = new uint16[](arrayLength);
        for (uint256 i = 0; i < arrayLength; i++) {
            leafArgumentIds[i] = SafeCast.toUint16(ids[i]);
        }
    }

    /// @inheritdoc IDeliberate
    function getUserRole(uint256 debateId, address account) external view override returns (User.Role role) {
        return _users[debateId][account].role;
    }

    /// @inheritdoc IDeliberate
    function getUserTokens(uint256 debateId, address account) external view override returns (uint32 tokens) {
        return _users[debateId][account].tokens;
    }

    /// @inheritdoc IDeliberate
    function getUserShares(uint256 debateId, uint16 argumentId, address account)
        external
        view
        override
        returns (User.Shares memory shares)
    {
        return _users[debateId][account].shares[argumentId];
    }

    /// @inheritdoc IDeliberate
    function debatesCount() external view override returns (uint256 count) {
        count = _debatesCounter;
    }

    /// @inheritdoc IDeliberate
    function debates(uint256 debateId)
        external
        view
        override
        returns (
            uint32 totalVotes,
            uint16 argumentsCount,
            uint32 participantsCount,
            uint8 feePercentage,
            IIdentityRegistry identityRegistry
        )
    {
        Debate.Data storage debate = _debates[debateId];
        return (
            debate.totalVotes,
            debate.argumentsCount,
            debate.participantsCount,
            debate.feePercentage,
            debate.identityRegistry
        );
    }

    /// @inheritdoc IDeliberate
    function bounty(uint256 debateId)
        external
        view
        override
        returns (IERC20 token, uint256 pool, uint256 claimed, bool swept, uint48 claimEndTime)
    {
        Bounty.Data storage bountyData = _bounties[debateId];
        uint48 finishTime = _phases[debateId].finishTime;
        claimEndTime = finishTime == 0 ? 0 : finishTime + Parameters.CLAIM_WINDOW;
        return (bountyData.token, bountyData.pool, bountyData.claimed, bountyData.swept, claimEndTime);
    }

    /// @inheritdoc IDeliberate
    function users(uint256 debateId, address account)
        external
        view
        override
        returns (User.Role role, uint32 tokens, bool bountyClaimed)
    {
        User.Data storage user = _users[debateId][account];
        return (user.role, user.tokens, user.bountyClaimed);
    }

    /// @inheritdoc IDeliberate
    function phases(uint256 debateId)
        external
        view
        override
        returns (Phase.Status currentPhase, uint48 editingEndTime, uint48 ratingEndTime, uint48 lockingDuration)
    {
        Phase.Data storage phaseData = _phases[debateId];
        return (_phaseOf(phaseData), phaseData.editingEndTime, phaseData.ratingEndTime, phaseData.lockingDuration);
    }

    /// @inheritdoc IDeliberate
    function outcome(uint256 debateId) external view override returns (bool approved) {
        Phase.Status currentPhase = _phaseOf(_phases[debateId]);
        if (currentPhase != Phase.Status.Finished) {
            revert PhaseInvalid({expected: Phase.Status.Finished, actual: currentPhase});
        }

        approved = _debates[debateId].arguments[0].descendantsNumerator > 0;
    }

    /// @inheritdoc IDeliberate
    /// @dev This requires the parent argument to be final: its editing window must have elapsed.
    function createArgument(
        uint256 debateId,
        uint16 parentArgumentId,
        string calldata content,
        bool isSupporting,
        uint8 initialApproval,
        uint32 deposit
    )
        public
        override
        onlyPhase(debateId, Phase.Status.Editing)
        onlyRole(debateId, User.Role.Participant)
        onlyFinalArgument(debateId, parentArgumentId)
        returns (uint16 newArgumentId)
    {
        User.Data storage user = _users[debateId][msg.sender];

        _checkContent(content);
        _checkInitialApproval(initialApproval);

        // The creator picks the deposit seeding the market; a floor keeps both reserves non-empty.
        if (deposit < Parameters._MIN_DEBATE_DEPOSIT) {
            revert DepositBelowMinimum({minimum: Parameters._MIN_DEBATE_DEPOSIT, actual: deposit});
        }

        if (user.tokens < deposit) {
            revert InsufficientVoteTokens({required: deposit, actual: user.tokens});
        }

        // initialize market
        Debate.Data storage debate = _debates[debateId];

        if (debate.getArgumentsCount() > Parameters.MAX_ARGUMENTS - 1) {
            revert ArgumentLimitReached({limit: Parameters.MAX_ARGUMENTS});
        }

        user.tokens -= deposit;

        // Create new argument
        newArgumentId = _createArgument({
            debateId: debateId,
            parentArgumentId: parentArgumentId,
            isSupporting: isSupporting,
            initialApproval: initialApproval,
            deposit: deposit
        });

        _updateParentAfterChildAttachment({debateId: debateId, parentArgumentId: parentArgumentId});

        // The deposit is committed to the new argument's market and counts toward the debate total.
        debate.totalVotes += deposit;

        // The new argument starts as a leaf.
        // slither-disable-next-line unused-return
        debate.leafArgumentIds.add(newArgumentId);

        Argument.Data storage newArgument = debate.arguments[newArgumentId];
        emit ArgumentCreated({
            debateId: debateId,
            argumentId: newArgumentId,
            parentArgumentId: parentArgumentId,
            creator: msg.sender,
            isSupporting: isSupporting,
            content: content,
            pro: newArgument.pro,
            con: newArgument.con,
            finalizationTime: newArgument.finalizationTime
        });
    }

    /// @inheritdoc IDeliberate
    function quoteStake(uint256 debateId, uint16 argumentId, bool isPro, uint32 voteTokenAmount)
        public
        view
        override
        returns (Argument.Stake memory stakeData)
    {
        Debate.Data storage debate = _debates[debateId];
        Argument.Data storage argument = debate.arguments[argumentId];

        stakeData.isPro = isPro;
        stakeData.voteTokensStaked = voteTokenAmount;
        stakeData.fee = voteTokenAmount.multiplyByFraction({numerator: debate.feePercentage, denominator: 100});

        uint32 net = voteTokenAmount - stakeData.fee;

        // Constant-product pricing: the opposite reserve absorbs the net stake,
        // the bought reserve is restored to the invariant - rounded up, so a reserve can never be
        // drained to zero - and the staker receives the freed shares plus the net amount.
        (uint32 bought, uint32 opposite) = isPro ? (argument.pro, argument.con) : (argument.con, argument.pro);
        uint32 newOpposite = opposite + net;
        uint32 newBought = bought.multiplyByFractionCeil({numerator: opposite, denominator: newOpposite});

        stakeData.sharesOut = bought + net - newBought;
    }

    /// @notice Internal function to create an argument below a parent argument with a certain initial approval.
    /// @param debateId The ID of the debate.
    /// @param parentArgumentId The ID of the parent argument.
    /// @param isSupporting Whether the argument supports or opposes the parent argument.
    /// @param initialApproval The initial approval of the argument.
    /// @param deposit The vote token deposit seeding the argument's market reserves.
    /// @return newArgumentId The ID of the created argument.
    function _createArgument(
        uint256 debateId,
        uint16 parentArgumentId,
        bool isSupporting,
        uint8 initialApproval,
        uint32 deposit
    ) internal returns (uint16 newArgumentId) {
        Debate.Data storage debate = _debates[debateId];

        newArgumentId = debate.getArgumentsCount();
        debate.incrementArgumentCounter();

        Argument.Data storage argument = debate.arguments[newArgumentId];

        // Seed the market reserves from the creator's deposit at their initial approval. Approval is the
        // pro-share PRICE, so a high approval means a scarce pro reserve: the con side receives
        // the initialApproval fraction of the deposit, the pro side the complement.
        (argument.pro, argument.con) = deposit.split(100 - initialApproval, initialApproval);
        argument.votes = deposit;

        // A fresh argument is a draft until its locking window elapses; existence and finality are
        // derived from the creator and this finalization time, so no state is stored.
        argument.creator = msg.sender;
        argument.finalizationTime = Time.timestamp() + _phases[debateId].lockingDuration;
        argument.parentArgumentId = parentArgumentId;
        argument.isSupporting = isSupporting;
    }

    /// @notice Internal function to update a parent argument after a child argument attaches to it in a debate.
    /// @dev The counterpart of `_updateParentAfterChildRemoval`; both maintain the child count the tally
    /// consumes and the leaf set it starts from, which is why they are one pair rather than open code at
    /// each of the three sites that attach or detach a child.
    /// @param debateId The ID of the debate.
    /// @param parentArgumentId The ID of the parent argument.
    function _updateParentAfterChildAttachment(uint256 debateId, uint16 parentArgumentId) internal {
        Debate.Data storage debate = _debates[debateId];

        // One more child to tally. Stake weights are not maintained here - the tally derives every
        // subtree's stake bottom-up when it runs.
        debate.arguments[parentArgumentId].untalliedChilds++;

        // The parent stops being a leaf on its first child. The removal is idempotent, so it is a
        // no-op if the parent was already interior, and the root is never a leaf: it has no market
        // and is never tallied as one.
        if (parentArgumentId != 0) {
            // slither-disable-next-line unused-return
            debate.leafArgumentIds.remove(parentArgumentId);
        }
    }

    /// @notice Internal function to update a parent argument after the removal of a child argument in a debate.
    /// @param debateId The ID of the debate.
    /// @param parentArgumentId The ID of the parent argument.
    function _updateParentAfterChildRemoval(uint256 debateId, uint16 parentArgumentId) internal {
        Debate.Data storage debate = _debates[debateId];
        Argument.Data storage parentArgument = debate.arguments[parentArgumentId];

        if (!_isFinal(parentArgument)) {
            revert ArgumentNotFinal({argumentId: parentArgumentId});
        }

        parentArgument.untalliedChilds--;

        // Eventually, the parent argument becomes a leaf after the removal - unless it is the root,
        // which has no market and is never tallied as a leaf.
        if (parentArgument.untalliedChilds == 0 && parentArgumentId != 0) {
            // slither-disable-next-line unused-return
            debate.leafArgumentIds.add(parentArgumentId);
        }
    }

    /// @notice Internal function pulling a bounty funding from the caller into the pool. The pool grows by
    /// what actually arrived (balance delta), so fee-on-transfer tokens fund what the contract can pay out.
    /// @param debateId The ID of the debate.
    /// @param amount The amount of the bounty token to pull from the caller.
    function _fundBounty(uint256 debateId, uint256 amount) internal {
        Bounty.Data storage bountyData = _bounties[debateId];
        IERC20 token = bountyData.token;

        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - balanceBefore;

        bountyData.pool += received;

        emit BountyFunded({
            debateId: debateId, funder: msg.sender, token: token, amount: received, pool: bountyData.pool
        });
    }

    /// @notice Internal function crediting an argument's accrued market fees to its creator; a no-op
    /// without fees.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    function _claimFees(uint256 debateId, uint16 argumentId) internal {
        Argument.Data storage argument = _debates[debateId].arguments[argumentId];

        uint32 fees = argument.fees;
        if (fees > 0) {
            argument.fees = 0;
            _users[debateId][argument.creator].tokens += fees;

            emit FeesClaimed({debateId: debateId, argumentId: argumentId, creator: argument.creator, fees: fees});
        }
    }

    /// @notice Internal function redeeming a user's shares in an argument for vote tokens; a no-op without shares.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param account The account to redeem the shares for.
    function _redeemArgumentShares(uint256 debateId, uint16 argumentId, address account) internal {
        User.Data storage user = _users[debateId][account];
        User.Shares storage userShares = _users[debateId][account].shares[argumentId];
        Argument.Data storage argument = _debates[debateId].arguments[argumentId];

        uint32 proShares = userShares.pro;
        uint32 conShares = userShares.con;
        if (proShares == 0 && conShares == 0) {
            return;
        }

        // A share settles against the tallied rating - the tree's verdict on the argument, not the
        // price its own market happened to close at: a pro share pays the rating mapped back onto
        // the price scale, a con share the complement. For a childless argument the rating is its
        // own time-weighted price, so the rule reduces to the market price wherever the tree had
        // nothing to say; for a debated one the sub-debate corrects the settlement in proportion
        // to the stake behind it. Rounding down keeps redemptions within what the market took in:
        // together the two prices pay out at most one full side's shares, which the market's
        // deposit and net stakes cover.
        uint256 proPrice = SafeCast.toUint256(int256(Parameters._MAX_APPROVAL) + argument.rating);
        uint256 fullScale = 2 * SafeCast.toUint256(int256(Parameters._MAX_APPROVAL));

        uint32 payout = 0;
        if (proShares > 0) {
            payout += SafeCast.toUint32(uint256(proShares) * proPrice / fullScale);
            userShares.pro = 0;
        }
        if (conShares > 0) {
            payout += SafeCast.toUint32(uint256(conShares) * (fullScale - proPrice) / fullScale);
            userShares.con = 0;
        }
        user.tokens += payout;

        emit SharesRedeemed({
            debateId: debateId,
            argumentId: argumentId,
            account: account,
            proShares: proShares,
            conShares: conShares,
            payout: payout
        });
    }

    /// @notice Internal function staking vote tokens on one side of an argument's constant-product market.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to stake on.
    /// @param isPro Whether pro or con shares are bought.
    /// @param voteTokenAmount The amount of vote tokens to stake.
    function _stake(uint256 debateId, uint16 argumentId, bool isPro, uint32 voteTokenAmount) internal {
        // The thesis is rated through its argument tree, not through a market of its own.
        if (argumentId == 0) {
            revert ThesisHasNoMarket();
        }

        User.Data storage user = _users[debateId][msg.sender];

        if (user.tokens < voteTokenAmount) {
            revert InsufficientVoteTokens({required: voteTokenAmount, actual: user.tokens});
        }

        user.tokens -= voteTokenAmount;

        Argument.Stake memory stakeData =
            quoteStake({debateId: debateId, argumentId: argumentId, isPro: isPro, voteTokenAmount: voteTokenAmount});

        uint32 net = voteTokenAmount - stakeData.fee;

        Debate.Data storage debate = _debates[debateId];
        Argument.Data storage argument = debate.arguments[argumentId];

        // The standing price and stake earn their held duration before the trade moves them.
        _accrueTallyInputs({debateId: debateId, argument: argument});

        // Reconstruct the post-trade reserves from the quote: the bought side shrinks by the
        // shares that leave the pool, the opposite side absorbs the net stake.
        if (isPro) {
            argument.pro = argument.pro + net - stakeData.sharesOut;
            argument.con += net;
            user.shares[argumentId].pro += stakeData.sharesOut;
        } else {
            argument.con = argument.con + net - stakeData.sharesOut;
            argument.pro += net;
            user.shares[argumentId].con += stakeData.sharesOut;
        }

        argument.votes += net;
        argument.fees += stakeData.fee;
        debate.totalVotes += net;

        emit Staked({debateId: debateId, argumentId: argumentId, staker: msg.sender, data: stakeData});
    }

    /// @notice Internal function to tally an argument in a debate, and then every ancestor the tally completes.
    /// @dev Walks up the tree in a loop rather than recursing into the parent. The parent step is a tail call, so
    /// the two are equivalent in effect - but each recursive frame consumes EVM stack, and a chain approaching the
    /// argument cap exhausted it, reverting with no error on the one transaction that can finish a debate and
    /// release its deposits.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    function _tallyNode(uint256 debateId, uint16 argumentId) internal {
        uint16 parentArgumentId;
        for (;; argumentId = parentArgumentId) {
            Argument.Data storage argument = _debates[debateId].arguments[argumentId];
            parentArgumentId = argument.parentArgumentId;
            Argument.Data storage parentArgument = _debates[debateId].arguments[parentArgumentId];

            if (argument.untalliedChilds > 0) {
                revert ChildsUntallied({untalliedChilds: argument.untalliedChilds});
            }

            // Only final arguments carry sway - those whose editing window elapsed. By the Tallying phase every
            // argument is final (its window ends before rating does), so this guards a case the phase clock rules
            // out.
            if (_isFinal(argument)) {
                // The argument's tallied rating: its own approval and its descendants' aggregate, each weighted
                // by the stake behind it. At this point `subtreeVotes` holds the tallied children's subtree
                // stakes; afterwards it holds the argument's full subtree stake (own time-weighted stake
                // included), the weight it folds in with.
                int40 rating = _calculateRating({debateId: debateId, argumentId: argumentId});
                uint32 subtreeVotes =
                    _timeWeightedVotes({debateId: debateId, argument: argument}) + argument.subtreeVotes;
                argument.subtreeVotes = subtreeVotes;
                // Stored for redemption to settle against: `subtreeVotes` is repurposed above, so the
                // rating could not be re-derived later without double-counting the argument's own stake.
                argument.rating = rating;

                emit ArgumentRated({
                    debateId: debateId, argumentId: argumentId, rating: rating, subtreeVotes: subtreeVotes
                });

                // A refuted argument is silenced, not inverted.
                int72 strength = rating > 0 ? int72(rating) : int72(0);

                // Add the stance-signed strength to the parent's numerator, weighted by the subtree stake.
                // Adding rather than averaging is what keeps the tally independent of the order the children
                // happen to be walked in: a sum is commutative where a mean rounded at every step is not.
                // The mean this is the numerator of is taken once, in `_calculateRating`.
                parentArgument.descendantsNumerator += (argument.isSupporting ? strength : -strength)
                    * int72(uint72(subtreeVotes));
                parentArgument.subtreeVotes += subtreeVotes;
            }

            parentArgument.untalliedChilds--;

            // Continue into the parent only once all of its children are tallied, and never into the root: the
            // root (the thesis) has no market and no parent of its own, and its `descendantsAggregate` - which
            // `outcome` reads - is complete once all of its children have been tallied.
            if (parentArgument.untalliedChilds != 0 || parentArgumentId == 0) {
                return;
            }
        }
    }

    /// @notice Internal function accruing an argument's time-weighted tally inputs - the centered approval and
    /// the market stake, each multiplied by the seconds they stood - up to now, capped at the rating window's
    /// end. Called before a trade moves the market; the tally itself never writes the accumulators (it
    /// completes them in memory), keeping the atomic whole-tree tally free of per-argument stores.
    /// @param debateId The ID of the debate.
    /// @param argument The argument whose accumulators are brought up to date.
    function _accrueTallyInputs(uint256 debateId, Argument.Data storage argument) internal {
        Phase.Data storage phaseData = _phases[debateId];

        // A zero accrual time marks untouched accumulators: the window opens when the rating phase does.
        uint48 start = argument.lastAccrualTime == 0 ? phaseData.editingEndTime : argument.lastAccrualTime;
        uint48 currentTime = Time.timestamp();
        uint48 until = currentTime < phaseData.ratingEndTime ? currentTime : phaseData.ratingEndTime;
        uint48 elapsed = until - start;
        if (elapsed == 0) {
            return;
        }

        argument.centeredApprovalSeconds += SafeCast.toInt88(
            int256(_centeredApproval(argument)) * int256(uint256(elapsed))
        );
        argument.votesSeconds += SafeCast.toUint80(uint256(argument.votes) * uint256(elapsed));
        argument.lastAccrualTime = until;
    }

    /// @notice An internal function reverting if the debate is not in a certain phase.
    /// @param debateId The ID of the debate.
    /// @param phase The phase of the debate required.
    function _onlyPhase(uint256 debateId, Phase.Status phase) internal view {
        Phase.Status currentPhase = _phaseOf(_phases[debateId]);
        if (currentPhase != phase) {
            revert PhaseInvalid({expected: phase, actual: currentPhase});
        }
    }

    /// @notice An internal function deriving a debate's phase from the time gates and the terminal tally latch.
    /// @dev Editing, Rating, and Tallying follow purely from the clock, so the phase never lags behind time and
    /// needs no poke to advance; only the terminal Finished phase is stored, latched by the tally. An unset
    /// `editingEndTime` marks a debate that was never created.
    /// @param phaseData The phase data of the debate.
    /// @return phase The current phase of the debate.
    function _phaseOf(Phase.Data storage phaseData) internal view returns (Phase.Status phase) {
        if (phaseData.editingEndTime == 0) {
            return Phase.Status.Uninitialized;
        }
        if (phaseData.finished) {
            return Phase.Status.Finished;
        }

        uint48 currentTime = Time.timestamp();
        if (currentTime > phaseData.ratingEndTime) {
            return Phase.Status.Tallying;
        }
        if (currentTime > phaseData.editingEndTime) {
            return Phase.Status.Rating;
        }
        return Phase.Status.Editing;
    }

    /// @notice An internal function reverting if the caller is not the argument creator.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    function _onlyCreator(uint256 debateId, uint16 argumentId) internal view {
        address creator = _debates[debateId].arguments[argumentId].creator;
        if (msg.sender != creator) {
            revert AddressInvalid({expected: creator, actual: msg.sender});
        }
    }

    /// @notice An internal function reverting if an argument is not final.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    function _onlyFinalArgument(uint256 debateId, uint16 argumentId) internal view {
        if (!_isFinal(_debates[debateId].arguments[argumentId])) {
            revert ArgumentNotFinal({argumentId: argumentId});
        }
    }

    /// @notice An internal function reverting if an argument is not an editable draft.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    function _onlyDraftArgument(uint256 debateId, uint16 argumentId) internal view {
        Argument.Data storage argument = _debates[debateId].arguments[argumentId];
        // A draft exists and is still inside its editing window: not the permanently-final thesis (whose window
        // ends at creation), not a window-elapsed (hence final) argument, and not a nonexistent one (no creator).
        if (argument.creator == address(0) || !_isDraft(argument)) {
            revert ArgumentNotDraft({argumentId: argumentId});
        }
    }

    /// @notice An internal function returning whether an argument is final: locked in, tradeable, and tallied.
    /// @dev Finality is derived, not stored: an argument is final once it exists and its editing window has
    /// elapsed. The thesis sets its finalization time to creation, so it is final from the start with no special
    /// case; a nonexistent argument (no creator) is never final, so its finalization time of zero is harmless.
    /// @param argument The argument to check.
    /// @return isFinal Whether the argument is final.
    function _isFinal(Argument.Data storage argument) internal view returns (bool isFinal) {
        isFinal = argument.creator != address(0) && !_isDraft(argument);
    }

    /// @notice An internal function returning whether an argument is still inside its editing window - the clock
    /// half of draft-ness, and the exact complement of window-elapsed finality; existence is the callers' check.
    /// @param argument The argument to check.
    /// @return isDraft Whether the argument's editing window is still running.
    function _isDraft(Argument.Data storage argument) internal view returns (bool isDraft) {
        isDraft = Time.timestamp() < argument.finalizationTime;
    }

    /// @notice An internal function reverting if the caller does not hold a certain role.
    /// @param debateId The ID of the debate.
    /// @param role The role required.
    function _onlyRole(uint256 debateId, User.Role role) internal view {
        User.Role currentRole = _users[debateId][msg.sender].role;
        if (currentRole != role) {
            revert RoleInvalid({expected: role, actual: currentRole});
        }
    }

    /// @notice Internal function to calculate the tallied rating of an argument in a debate. Requires the
    /// argument's accumulators to be complete: accrued through the rating window's end.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @return rating The tallied rating of the argument - signed, negative meaning refuted.
    function _calculateRating(uint256 debateId, uint16 argumentId) internal view returns (int40 rating) {
        Argument.Data storage argument = _debates[debateId].arguments[argumentId];

        // The own approval, centered so the market's undecided price is zero and time-weighted over the
        // rating window: what the market said, for as long as it said it. A push in the window's closing
        // seconds moves this average by the tail fraction only.
        (int88 centeredApprovalSeconds,) = _completedTallyInputs({debateId: debateId, argument: argument});
        uint48 window = _phases[debateId].ratingEndTime - _phases[debateId].editingEndTime;
        int64 centeredApproval = SafeCast.toInt64(int256(centeredApprovalSeconds) / int256(uint256(window)));

        // Blend own approval and the descendants' sways by the stake behind each: the argument's own
        // time-weighted market stake against its subtree's (accumulated by the tallied children). A childless
        // argument keeps its full own centered approval; a heavily debated one is corrected in proportion
        // to the stake that debate attracted. The denominator is at least the argument's deposit - which
        // stands the whole window, so its time-weighted stake is itself - never zero. Negative means
        // refuted: the debate rates this argument as standing against itself.
        //
        // One division, over the summed numerator: the descendants enter as
        // `Σ sway * subtreeStake` rather than as a mean already rounded once per child, so nothing is lost
        // between the children and here and the result cannot depend on the order they were folded in.
        uint32 ownVotes = _timeWeightedVotes({debateId: debateId, argument: argument});
        rating = SafeCast.toInt40(
            (int256(centeredApproval) * int256(uint256(ownVotes)) + int256(argument.descendantsNumerator))
                / int256(uint256(ownVotes) + uint256(argument.subtreeVotes))
        );
    }

    /// @notice An internal function reading an argument market's current approval, centered so the undecided
    /// 50% price is zero.
    /// @param argument The argument whose market is read.
    /// @return centeredApproval The centered approval, in the tally's fixed point.
    function _centeredApproval(Argument.Data storage argument) internal view returns (int64 centeredApproval) {
        uint32 pro = argument.pro;
        uint32 con = argument.con;

        centeredApproval = Parameters._MAX_APPROVAL
            .multiplyByFraction({
                numerator: int64(uint64(con)) - int64(uint64(pro)), denominator: int64(uint64(pro)) + int64(uint64(con))
            });
    }

    /// @notice An internal function completing an argument's time-weighted accumulators in memory: the stored
    /// sums plus the stretch from the last accrual to the rating window's end at the standing values. Nothing
    /// trades after rating ends, so the standing values are the final ones - the whole-tree tally reads
    /// completed accumulators without a single per-argument store. Meaningful once rating has ended.
    /// @param debateId The ID of the debate.
    /// @param argument The argument whose accumulators are completed.
    /// @return centeredApprovalSeconds The completed centered-approval accumulator.
    /// @return votesSeconds The completed stake accumulator.
    function _completedTallyInputs(uint256 debateId, Argument.Data storage argument)
        internal
        view
        returns (int88 centeredApprovalSeconds, uint80 votesSeconds)
    {
        Phase.Data storage phaseData = _phases[debateId];

        // A zero accrual time marks untouched accumulators: the window opens when the rating phase does.
        uint48 start = argument.lastAccrualTime == 0 ? phaseData.editingEndTime : argument.lastAccrualTime;
        uint48 elapsed = phaseData.ratingEndTime - start;

        centeredApprovalSeconds = argument.centeredApprovalSeconds
            + SafeCast.toInt88(int256(_centeredApproval(argument)) * int256(uint256(elapsed)));
        votesSeconds = argument.votesSeconds + SafeCast.toUint80(uint256(argument.votes) * uint256(elapsed));
    }

    /// @notice An internal function reading an argument's time-weighted stake: the vote tokens held in its
    /// market, averaged over the rating window. A stake placed mid-window counts in proportion to the time it
    /// was held and exposed; the deposit, standing the whole window, counts in full. Meaningful once rating
    /// has ended.
    /// @param debateId The ID of the debate.
    /// @param argument The argument whose stake is read.
    /// @return timeWeightedVotes The time-weighted stake.
    function _timeWeightedVotes(uint256 debateId, Argument.Data storage argument)
        internal
        view
        returns (uint32 timeWeightedVotes)
    {
        (, uint80 votesSeconds) = _completedTallyInputs({debateId: debateId, argument: argument});
        uint48 window = _phases[debateId].ratingEndTime - _phases[debateId].editingEndTime;

        // An average of uint32 stake levels stays within uint32.
        timeWeightedVotes = SafeCast.toUint32(uint256(votesSeconds) / window);
    }

    /// @notice An internal function reverting if an initial approval is outside the seedable range.
    /// @param initialApproval The initial approval to validate.
    function _checkInitialApproval(uint8 initialApproval) internal pure {
        if (initialApproval < 50) {
            revert InitialApprovalOutOfBounds({limit: 50, actual: initialApproval});
        }
        // 100 is not seedable: it would empty the pro reserve and freeze the market.
        if (initialApproval > 99) {
            revert InitialApprovalOutOfBounds({limit: 99, actual: initialApproval});
        }
    }

    /// @notice An internal function reverting if content is empty or longer than the permitted maximum.
    /// @dev Content is published by the event that follows and never stored, so the bounds are on calldata and
    /// log size - in bytes of UTF-8, which is all the chain can count.
    /// @param content The content to validate.
    function _checkContent(string calldata content) internal pure {
        uint256 length = bytes(content).length;
        if (length == 0) {
            revert ContentEmpty();
        }
        if (length > Parameters.MAX_CONTENT_LENGTH) {
            revert ContentTooLong({limit: Parameters.MAX_CONTENT_LENGTH, actual: length});
        }
    }
}
