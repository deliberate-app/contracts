// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {SafeCast} from "@openzeppelin-contracts-5.6.1/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin-contracts-5.6.1/utils/structs/EnumerableSet.sol";
import {Time} from "@openzeppelin-contracts-5.6.1/utils/types/Time.sol";

import {IArborVote} from "./interfaces/IArborVote.sol";
import {IProofOfHumanity} from "./interfaces/IProofOfHumanity.sol";
import {Argument} from "./libs/Argument.sol";
import {Debate} from "./libs/Debate.sol";
import {Phase} from "./libs/Phase.sol";
import {User} from "./libs/User.sol";
import {Utils} from "./libs/Utils.sol";

/// @title ArborVote
/// @author Michael Heuer
/// @notice A voting module for deliberative decision-making using argument trees. The contract is deployed once,
/// has no owner, and is not upgradeable; state lives in ERC-7201 namespaced storage.
contract ArborVote is IArborVote {
    using EnumerableSet for EnumerableSet.UintSet;
    using Utils for uint32;
    using Utils for int64;
    using Debate for Debate.Data;

    /// @notice The [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) storage of the contract.
    /// @param poh The proof of humanity registry contract (PoH mainnet: 0x1dAD862095d40d43c2109370121cf087632874dB).
    /// @param debatesCounter The counter tracking the number of created debates.
    /// @param debates The debates by their ID.
    /// @param users The users by debate ID and account.
    /// @param phases The phase data by debate ID.
    /// @custom:storage-location erc7201:arborvote.storage.ArborVote
    struct ArborVoteStorage {
        IProofOfHumanity poh;
        uint256 debatesCounter;
        mapping(uint256 debateId => Debate.Data) debates;
        mapping(uint256 debateId => mapping(address account => User.Data)) users;
        mapping(uint256 debateId => Phase.Data) phases;
    }

    uint32 internal constant _DEBATE_DEPOSIT = 10;
    uint32 internal constant _FEE_PERCENTAGE = 5;

    /// @notice The initial vote token balance granted to a user upon joining a debate.
    uint32 public constant INITIAL_TOKENS = 100;

    /// @notice The maximum number of arguments per debate, the thesis included.
    /// @dev Bounds the atomic tally: the whole tree must be tallyable within one block's gas (asserted by the gas
    /// benchmark test). Depth needs no bound of its own - each tree level takes one time unit of finalization
    /// latency inside the seven-time-unit editing window - so the cap effectively governs breadth.
    uint16 public constant MAX_ARGUMENTS = 1024;

    int64 internal constant _MIX_VAL = type(int64).max / 2;
    int64 internal constant _MIX_MAX = type(int64).max;

    /// @notice The fixed-point scale of an argument's own approval impact (full approval equals `type(uint32).max`).
    int64 internal constant _MAX_APPROVAL = int64(uint64(type(uint32).max));

    /// @notice The ERC-7201 storage location of the ArborVote contract (see https://eips.ethereum.org/EIPS/eip-7201).
    /// @dev Obtained from
    /// `keccak256(abi.encode(uint256(keccak256("arborvote.storage.ArborVote")) - 1)) & ~bytes32(uint256(0xff))`.
    bytes32 internal constant _ARBORVOTE_STORAGE_LOCATION =
        0x7bc2c952758c3eed6da7b2b2d780739da4d5723529f239fb18a0ce0c647a4300;

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

    /// @notice Thrown if the state of an argument is invalid.
    /// @param expected The expected argument state.
    /// @param actual The actual argument state.
    error StateInvalid(Argument.State expected, Argument.State actual);

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

    /// @notice Thrown if initial approval value is out of bounds.
    /// @param limit The limit initial approval value.
    /// @param actual The actual initial approval value.
    error InitialApprovalOutOfBounds(uint32 limit, uint32 actual);

    /// @notice Thrown if the vote token balance is too low.
    /// @param required The required vote tokens.
    /// @param actual The actual vote token balance.
    error InsufficientVoteTokens(uint32 required, uint32 actual);

    /// @notice Thrown if a debate has reached its maximum number of arguments.
    /// @param limit The maximum number of arguments per debate.
    error ArgumentLimitReached(uint16 limit);

    /// @notice Thrown if the thesis (argument 0), which has no market, is invested in.
    error ThesisHasNoMarket();

    /// @notice Thrown if the childs of the argument are not tallied.
    /// @param untalliedChilds The number of untallied childs.
    error ChildsUntallied(uint16 untalliedChilds);

    /// @notice A modifier to restrict functions to only be called if the debate is in a certain phase.
    /// @param debateId The ID of the debate.
    /// @param phase The phase of the debate required.
    modifier onlyPhase(uint256 debateId, Phase.Status phase) {
        _onlyPhase({debateId: debateId, phase: phase});
        _;
    }

    /// @notice A modifier to restrict functions to only be called if the argument is in a certain state.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param state The state of the argument required.
    modifier onlyArgumentState(uint256 debateId, uint16 argumentId, Argument.State state) {
        _onlyArgumentState({debateId: debateId, argumentId: argumentId, state: state});
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

    /// @notice Deploys the contract with the Proof of Humanity registry gating debate joining.
    /// @param poh The proof of humanity registry contract.
    constructor(IProofOfHumanity poh) {
        _getArborVoteStorage().poh = poh;
    }

    /// @inheritdoc IArborVote
    function createDebate(bytes32 contentURI, uint48 timeUnit)
        external
        override
        onlyArgumentState(_getArborVoteStorage().debatesCounter, 0, Argument.State.Uninitialized)
        returns (uint256 debateId)
    {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        debateId = $.debatesCounter;
        $.debatesCounter++;

        // Create the root Argument
        Debate.Data storage newDebate = $.debates[debateId];
        Argument.Data storage rootArgument = newDebate.arguments[0];

        // Create the root argument of the tree
        rootArgument.contentURI = contentURI;

        rootArgument.creator = msg.sender;
        rootArgument.finalizationTime = Time.timestamp();
        rootArgument.state = Argument.State.Final;

        // Store the phase related data
        Phase.Data storage phaseData = $.phases[debateId];
        phaseData.currentPhase = Phase.Status.Editing;
        phaseData.timeUnit = timeUnit;
        phaseData.editingEndTime = Time.timestamp() + 7 * timeUnit;
        phaseData.ratingEndTime = Time.timestamp() + 10 * timeUnit;

        // increment counters
        newDebate.incrementArgumentCounter();

        emit ArgumentUpdated({debateId: debateId, argumentId: 0, parentArgumentId: 0, contentURI: contentURI});
    }

    /// @inheritdoc IArborVote
    function join(uint256 debateId) external override onlyRole(debateId, User.Role.Unassigned) {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        // Joining is only possible while participating is: during the editing and rating phases.
        Phase.Status currentPhase = $.phases[debateId].currentPhase;
        if (currentPhase == Phase.Status.Uninitialized) {
            revert DebateUninitialized({debateId: debateId});
        }
        if (currentPhase > Phase.Status.Rating) {
            revert PhaseExceeded({limit: Phase.Status.Rating, actual: currentPhase});
        }

        if (!$.poh.isRegistered(msg.sender)) {
            revert IdentityProofInvalid();
        } // not failsafe - takes 3.5 days to switch address

        User.Data storage user = $.users[debateId][msg.sender];

        user.role = User.Role.Participant;
        user.tokens = INITIAL_TOKENS;
    }

    /// @inheritdoc IArborVote
    /// @dev The new parent must be final, mirroring `addArgument`. This also rules out cycles: children only ever
    /// attach beneath Final arguments while only Created arguments can move, so a Created argument is always
    /// childless - its subtree is itself alone, and it is not Final.
    function moveArgument(uint256 debateId, uint16 argumentId, uint16 newParentArgumentId)
        external
        override
        onlyPhase(debateId, Phase.Status.Editing)
        onlyCreator(debateId, argumentId)
        onlyArgumentState(debateId, argumentId, Argument.State.Created)
        onlyArgumentState(debateId, newParentArgumentId, Argument.State.Final)
    {
        Debate.Data storage debate = _getArborVoteStorage().debates[debateId];
        Argument.Data storage movedArgument = debate.arguments[argumentId];

        // change old parent's argument state
        uint16 oldParentArgumentId = movedArgument.parentArgumentId;
        _updateParentAfterChildRemoval({debateId: debateId, parentArgumentId: oldParentArgumentId});
        debate.arguments[oldParentArgumentId].childsVote -= movedArgument.votes;

        // change argument state
        movedArgument.parentArgumentId = newParentArgumentId;

        // change new parent argument state
        debate.arguments[newParentArgumentId].untalliedChilds++;
        debate.arguments[newParentArgumentId].childsVote += movedArgument.votes;
        if (newParentArgumentId != 0) {
            // The removal is idempotent: a no-op if the new parent was already interior.
            // slither-disable-next-line unused-return
            debate.leafArgumentIds.remove(newParentArgumentId);
        }

        emit ArgumentUpdated({
            debateId: debateId,
            argumentId: argumentId,
            parentArgumentId: newParentArgumentId,
            contentURI: movedArgument.contentURI
        });
    }

    /// @inheritdoc IArborVote
    function alterArgument(uint256 debateId, uint16 argumentId, bytes32 contentURI)
        external
        override
        onlyPhase(debateId, Phase.Status.Editing)
        onlyCreator(debateId, argumentId)
        onlyArgumentState(debateId, argumentId, Argument.State.Created)
    {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        uint48 newFinalizationTime = Time.timestamp() + $.phases[debateId].timeUnit;

        if (newFinalizationTime > $.phases[debateId].editingEndTime) {
            revert TimeOutOfBounds({limit: $.phases[debateId].editingEndTime, actual: newFinalizationTime});
        }

        Argument.Data storage alteredArgument = $.debates[debateId].arguments[argumentId];
        alteredArgument.finalizationTime = newFinalizationTime;
        alteredArgument.contentURI = contentURI;

        emit ArgumentUpdated({
            debateId: debateId,
            argumentId: argumentId,
            parentArgumentId: alteredArgument.parentArgumentId,
            contentURI: contentURI
        });
    }

    /// @inheritdoc IArborVote
    function investInPro(uint256 debateId, uint16 argumentId, uint32 voteTokenAmount)
        external
        override
        onlyPhase(debateId, Phase.Status.Rating)
        onlyArgumentState(debateId, argumentId, Argument.State.Final)
    {
        _invest({debateId: debateId, argumentId: argumentId, isPro: true, voteTokenAmount: voteTokenAmount});
    }

    /// @inheritdoc IArborVote
    function investInCon(uint256 debateId, uint16 argumentId, uint32 voteTokenAmount)
        external
        override
        onlyPhase(debateId, Phase.Status.Rating)
        onlyArgumentState(debateId, argumentId, Argument.State.Final)
    {
        _invest({debateId: debateId, argumentId: argumentId, isPro: false, voteTokenAmount: voteTokenAmount});
    }

    /// @inheritdoc IArborVote
    function tallyTree(uint256 debateId) external override onlyPhase(debateId, Phase.Status.Tallying) {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        uint256[] memory leafArgumentIds = $.debates[debateId].leafArgumentIds.values();

        uint256 arrayLength = leafArgumentIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            _tallyNode(debateId, SafeCast.toUint16(leafArgumentIds[i]));
        }

        $.phases[debateId].currentPhase = Phase.Status.Finished;
    }

    /// @inheritdoc IArborVote
    function redeemArgumentShares(uint256 debateId, uint16 argumentId, address account)
        external
        override
        onlyPhase(debateId, Phase.Status.Finished)
    {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        User.Data storage user = $.users[debateId][account];
        User.Shares storage userShares = $.users[debateId][account].shares[argumentId];
        Argument.Data storage argument = $.debates[debateId].arguments[argumentId];

        uint32 marketSize = argument.pro + argument.con;

        // Each pro share pays out the final approval - the con reserve's share of the market
        // - and each con share the complement. Rounding down keeps the market solvent.
        if (userShares.pro > 0) {
            user.tokens += userShares.pro.multiplyByFraction({numerator: argument.con, denominator: marketSize});
            userShares.pro = 0;
        }
        if (userShares.con > 0) {
            user.tokens += userShares.con.multiplyByFraction({numerator: argument.pro, denominator: marketSize});
            userShares.con = 0;
        }
    }

    /// @inheritdoc IArborVote
    function claimFees(uint256 debateId, uint16 argumentId)
        external
        override
        onlyPhase(debateId, Phase.Status.Finished)
    {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        Argument.Data storage argument = $.debates[debateId].arguments[argumentId];

        uint32 fees = argument.fees;
        if (fees > 0) {
            argument.fees = 0;
            $.users[debateId][argument.creator].tokens += fees;

            emit FeesClaimed({debateId: debateId, argumentId: argumentId, creator: argument.creator, fees: fees});
        }
    }

    /// @inheritdoc IArborVote
    function getArgument(uint256 debateId, uint16 argumentId)
        external
        view
        override
        returns (Argument.Data memory argument)
    {
        return _getArborVoteStorage().debates[debateId].arguments[argumentId];
    }

    /// @inheritdoc IArborVote
    function getLeafArgumentIds(uint256 debateId) external view override returns (uint16[] memory leafArgumentIds) {
        uint256[] memory ids = _getArborVoteStorage().debates[debateId].leafArgumentIds.values();

        leafArgumentIds = new uint16[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            leafArgumentIds[i] = SafeCast.toUint16(ids[i]);
        }
    }

    /// @inheritdoc IArborVote
    function getUserRole(uint256 debateId, address account) external view override returns (User.Role role) {
        return _getArborVoteStorage().users[debateId][account].role;
    }

    /// @inheritdoc IArborVote
    function getUserTokens(uint256 debateId, address account) external view override returns (uint32 tokens) {
        return _getArborVoteStorage().users[debateId][account].tokens;
    }

    /// @inheritdoc IArborVote
    function getUserShares(uint256 debateId, uint16 argumentId, address account)
        external
        view
        override
        returns (User.Shares memory shares)
    {
        return _getArborVoteStorage().users[debateId][account].shares[argumentId];
    }

    /// @inheritdoc IArborVote
    function debates(uint256 debateId) external view override returns (uint32 totalVotes, uint16 argumentsCount) {
        Debate.Data storage debate = _getArborVoteStorage().debates[debateId];
        return (debate.totalVotes, debate.argumentsCount);
    }

    /// @inheritdoc IArborVote
    function users(uint256 debateId, address account) external view override returns (User.Role role, uint32 tokens) {
        User.Data storage user = _getArborVoteStorage().users[debateId][account];
        return (user.role, user.tokens);
    }

    /// @inheritdoc IArborVote
    function phases(uint256 debateId)
        external
        view
        override
        returns (Phase.Status currentPhase, uint48 editingEndTime, uint48 ratingEndTime, uint48 timeUnit)
    {
        Phase.Data storage phaseData = _getArborVoteStorage().phases[debateId];
        return (phaseData.currentPhase, phaseData.editingEndTime, phaseData.ratingEndTime, phaseData.timeUnit);
    }

    /// @inheritdoc IArborVote
    function outcome(uint256 debateId) external view override returns (bool approved) {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        if ($.phases[debateId].currentPhase != Phase.Status.Finished) {
            revert PhaseInvalid({expected: Phase.Status.Finished, actual: $.phases[debateId].currentPhase});
        }

        approved = $.debates[debateId].arguments[0].childsImpact > 0;
    }

    /// @inheritdoc IArborVote
    function advancePhase(uint256 debateId) public override {
        Phase.Data storage phaseData = _getArborVoteStorage().phases[debateId];

        Phase.Status currentPhase = phaseData.currentPhase;

        if (currentPhase == Phase.Status.Uninitialized) {
            revert DebateUninitialized({debateId: debateId});
        }

        // The terminal phase is entered by the tally and can never be left.
        if (currentPhase == Phase.Status.Finished) {
            return;
        }

        uint48 currentTime = Time.timestamp();

        if (currentTime > phaseData.ratingEndTime) {
            phaseData.currentPhase = Phase.Status.Tallying;
        } else if (currentTime > phaseData.editingEndTime) {
            phaseData.currentPhase = Phase.Status.Rating;
        }
    }

    /// @inheritdoc IArborVote
    function finalizeArgument(uint256 debateId, uint16 argumentId)
        public
        override
        onlyArgumentState(debateId, argumentId, Argument.State.Created)
    {
        Argument.Data storage argument = _getArborVoteStorage().debates[debateId].arguments[argumentId];

        uint48 currentTime = Time.timestamp();

        if (argument.finalizationTime > currentTime) {
            revert TimeOutOfBounds({limit: currentTime, actual: argument.finalizationTime});
        }

        argument.state = Argument.State.Final;
    }

    /// @inheritdoc IArborVote
    /// @dev This requires the parent argument to be final.
    function addArgument(
        uint256 debateId,
        uint16 parentArgumentId,
        bytes32 contentURI,
        bool isSupporting,
        uint32 initialApproval
    )
        public
        override
        onlyPhase(debateId, Phase.Status.Editing)
        onlyRole(debateId, User.Role.Participant)
        onlyArgumentState(debateId, parentArgumentId, Argument.State.Final)
        returns (uint16 newArgumentId)
    {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        User.Data storage user = $.users[debateId][msg.sender];

        if (initialApproval < 50) {
            revert InitialApprovalOutOfBounds({limit: 50, actual: initialApproval});
        }
        // 100 is not seedable: it would empty the pro reserve and freeze the market.
        if (initialApproval > 99) {
            revert InitialApprovalOutOfBounds({limit: 99, actual: initialApproval});
        }

        if (user.tokens < _DEBATE_DEPOSIT) {
            revert InsufficientVoteTokens({required: _DEBATE_DEPOSIT, actual: user.tokens});
        }

        // initialize market
        Debate.Data storage debate = $.debates[debateId];

        if (debate.getArgumentsCount() >= MAX_ARGUMENTS) {
            revert ArgumentLimitReached({limit: MAX_ARGUMENTS});
        }

        user.tokens -= _DEBATE_DEPOSIT;

        // Create new argument
        newArgumentId = _createArgument({
            debateId: debateId,
            parentArgumentId: parentArgumentId,
            contentURI: contentURI,
            isSupporting: isSupporting,
            initialApproval: initialApproval
        });

        // Update the parent: one more child to tally whose deposit counts toward the children's vote weight.
        Argument.Data storage parentArgument = debate.arguments[parentArgumentId];
        parentArgument.untalliedChilds++;
        parentArgument.childsVote += _DEBATE_DEPOSIT;

        // The deposit is committed to the new argument's market and counts toward the debate total.
        debate.totalVotes += _DEBATE_DEPOSIT;

        // Update the debate's leaves: the parent stops being one (a no-op if it was already interior,
        // and the root is never a leaf), the new argument starts as one.
        if (parentArgumentId != 0) {
            // slither-disable-next-line unused-return
            debate.leafArgumentIds.remove(parentArgumentId);
        }
        // slither-disable-next-line unused-return
        debate.leafArgumentIds.add(newArgumentId);

        emit ArgumentUpdated({
            debateId: debateId, argumentId: newArgumentId, parentArgumentId: parentArgumentId, contentURI: contentURI
        });
    }

    /// @inheritdoc IArborVote
    function calculateInvestment(uint256 debateId, uint16 argumentId, bool isPro, uint32 voteTokenAmount)
        public
        view
        override
        returns (Argument.Investment memory investmentData)
    {
        Argument.Data storage argument = _getArborVoteStorage().debates[debateId].arguments[argumentId];

        investmentData.isPro = isPro;
        investmentData.voteTokensInvested = voteTokenAmount;
        investmentData.fee = voteTokenAmount.multiplyByFraction({numerator: _FEE_PERCENTAGE, denominator: 100});

        uint32 net = voteTokenAmount - investmentData.fee;

        // Constant-product pricing: the opposite reserve absorbs the net investment,
        // the bought reserve is restored to the invariant - rounded up, so a reserve can never be
        // drained to zero - and the investor receives the freed shares plus the net amount.
        (uint32 bought, uint32 opposite) = isPro ? (argument.pro, argument.con) : (argument.con, argument.pro);
        uint32 newOpposite = opposite + net;
        uint32 newBought = bought.multiplyByFractionCeil({numerator: opposite, denominator: newOpposite});

        investmentData.sharesOut = bought + net - newBought;
    }

    /// @notice Internal function to create an argument below a parent argument with a certain initial approval.
    /// @param debateId The ID of the debate.
    /// @param parentArgumentId The ID of the parent argument.
    /// @param contentURI The URI pointing to the argument content.
    /// @param isSupporting Whether the argument supports or opposes the parent argument.
    /// @param initialApproval The initial approval of the argument.
    /// @return newArgumentId The ID of the created argument.
    function _createArgument(
        uint256 debateId,
        uint16 parentArgumentId,
        bytes32 contentURI,
        bool isSupporting,
        uint32 initialApproval
    ) internal returns (uint16 newArgumentId) {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        Debate.Data storage debate = $.debates[debateId];

        newArgumentId = debate.getArgumentsCount();
        debate.incrementArgumentCounter();

        Argument.Data storage argument = debate.arguments[newArgumentId];

        // Seed the market reserves at the creator's initial approval. Approval is the pro-share
        // PRICE, so a high approval means a scarce pro reserve: the con side receives
        // the initialApproval fraction of the deposit, the pro side the complement.
        (argument.pro, argument.con) = _DEBATE_DEPOSIT.split(100 - initialApproval, initialApproval);
        argument.votes = _DEBATE_DEPOSIT;

        argument.creator = msg.sender;
        argument.finalizationTime = Time.timestamp() + $.phases[debateId].timeUnit;
        argument.parentArgumentId = parentArgumentId;
        argument.isSupporting = isSupporting;
        argument.state = Argument.State.Created;

        argument.contentURI = contentURI;
    }

    /// @notice Internal function to update a parent argument after the removal of a child argument in a debate.
    /// @param debateId The ID of the debate.
    /// @param parentArgumentId The ID of the parent argument.
    function _updateParentAfterChildRemoval(uint256 debateId, uint16 parentArgumentId) internal {
        Debate.Data storage debate = _getArborVoteStorage().debates[debateId];
        Argument.Data storage parentArgument = debate.arguments[parentArgumentId];

        if (parentArgument.state != Argument.State.Final) {
            revert StateInvalid({expected: Argument.State.Final, actual: parentArgument.state});
        }

        parentArgument.untalliedChilds--;

        // Eventually, the parent argument becomes a leaf after the removal - unless it is the root,
        // which has no market and is never tallied as a leaf.
        if (parentArgument.untalliedChilds == 0 && parentArgumentId != 0) {
            // slither-disable-next-line unused-return
            debate.leafArgumentIds.add(parentArgumentId);
        }
    }

    /// @notice Internal function investing vote tokens into one side of an argument's constant-product market.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to invest in.
    /// @param isPro Whether pro or con shares are bought.
    /// @param voteTokenAmount The amount of vote tokens to invest.
    function _invest(uint256 debateId, uint16 argumentId, bool isPro, uint32 voteTokenAmount) internal {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        // The thesis is rated through its argument tree, not through a market of its own.
        if (argumentId == 0) {
            revert ThesisHasNoMarket();
        }

        User.Data storage user = $.users[debateId][msg.sender];

        if (user.tokens < voteTokenAmount) {
            revert InsufficientVoteTokens({required: voteTokenAmount, actual: user.tokens});
        }

        user.tokens -= voteTokenAmount;

        Argument.Investment memory investment = calculateInvestment({
            debateId: debateId, argumentId: argumentId, isPro: isPro, voteTokenAmount: voteTokenAmount
        });

        uint32 net = voteTokenAmount - investment.fee;

        Debate.Data storage debate = $.debates[debateId];
        Argument.Data storage argument = debate.arguments[argumentId];

        // Reconstruct the post-trade reserves from the quote: the bought side shrinks by the
        // shares that leave the pool, the opposite side absorbs the net investment.
        if (isPro) {
            argument.pro = argument.pro + net - investment.sharesOut;
            argument.con += net;
            user.shares[argumentId].pro += investment.sharesOut;
        } else {
            argument.con = argument.con + net - investment.sharesOut;
            argument.pro += net;
            user.shares[argumentId].con += investment.sharesOut;
        }

        argument.votes += net;
        argument.fees += investment.fee;
        debate.totalVotes += net;
        debate.arguments[argument.parentArgumentId].childsVote += net;

        emit Invested({debateId: debateId, argumentId: argumentId, investor: msg.sender, data: investment});
    }

    /// @notice Internal function to tally an argument in a debate.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    function _tallyNode(uint256 debateId, uint16 argumentId) internal {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        Argument.Data storage argument = $.debates[debateId].arguments[argumentId];
        uint16 parentArgumentId = argument.parentArgumentId;
        Argument.Data storage parentArgument = $.debates[debateId].arguments[parentArgumentId];

        if (argument.untalliedChilds > 0) {
            revert ChildsUntallied({untalliedChilds: argument.untalliedChilds});
        }

        // Only Final arguments carry impact. An argument never finalized contributes nothing: it can have
        // neither children nor investors (both require a Final argument), only its author's never-locked-in signal.
        int64 ownImpact = 0;
        if (argument.state == Argument.State.Final) {
            // Calculate own impact $r_j$
            ownImpact = _calculateImpact({debateId: debateId, argumentId: argumentId});

            // Apply pre-factor $\sigma_j$
            if (!argument.isSupporting) {
                ownImpact = -ownImpact;
            }

            // Apply weight $w_j$. The parent holds the summed votes of all its children (the siblings).
            ownImpact =
                ownImpact.multiplyByFraction({numerator: argument.votes, denominator: parentArgument.childsVote});
        }

        // Update the parent argument impact
        parentArgument.childsImpact += ownImpact;
        parentArgument.untalliedChilds--;

        // If all children of the parent are tallied, tally the parent - unless the parent is the root: the root
        // (the thesis) has no market and no parent of its own, and its `childsImpact` - which `outcome` reads -
        // is complete once all of its children have been tallied.
        if (parentArgument.untalliedChilds == 0 && parentArgumentId != 0) {
            _tallyNode({debateId: debateId, argumentId: parentArgumentId});
        }

        emit ArgumentImpactCalculated({debateId: debateId, argumentId: argumentId, impact: ownImpact});
    }

    /// @notice An internal function reverting if the debate is not in a certain phase.
    /// @param debateId The ID of the debate.
    /// @param phase The phase of the debate required.
    function _onlyPhase(uint256 debateId, Phase.Status phase) internal view {
        ArborVoteStorage storage $ = _getArborVoteStorage();
        if ($.phases[debateId].currentPhase != phase) {
            revert PhaseInvalid({expected: phase, actual: $.phases[debateId].currentPhase});
        }
    }

    /// @notice An internal function reverting if the caller is not the argument creator.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    function _onlyCreator(uint256 debateId, uint16 argumentId) internal view {
        address creator = _getArborVoteStorage().debates[debateId].arguments[argumentId].creator;
        if (msg.sender != creator) {
            revert AddressInvalid({expected: creator, actual: msg.sender});
        }
    }

    /// @notice An internal function reverting if the argument is not in a certain state.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param state The state of the argument required.
    function _onlyArgumentState(uint256 debateId, uint16 argumentId, Argument.State state) internal view {
        Argument.State currentState = _getArborVoteStorage().debates[debateId].arguments[argumentId].state;
        if (currentState != state) {
            revert StateInvalid({expected: state, actual: currentState});
        }
    }

    /// @notice An internal function reverting if the caller does not hold a certain role.
    /// @param debateId The ID of the debate.
    /// @param role The role required.
    function _onlyRole(uint256 debateId, User.Role role) internal view {
        User.Role currentRole = _getArborVoteStorage().users[debateId][msg.sender].role;
        if (currentRole != role) {
            revert RoleInvalid({expected: role, actual: currentRole});
        }
    }

    /// @notice Internal function to calculate the impact of an argument in a debate.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @return impact The impact of the argument.
    function _calculateImpact(uint256 debateId, uint16 argumentId) internal view returns (int64 impact) {
        Argument.Data storage argument = _getArborVoteStorage().debates[debateId].arguments[argumentId];

        uint32 pro = argument.pro;
        uint32 con = argument.con;

        // Calculate the own approval impact. Approval is the pro-share PRICE of the market:
        // the scarcer the pro reserve, the higher the approval - i.e. con/(pro+con).
        impact = _MAX_APPROVAL.multiplyByFraction({numerator: con, denominator: pro + con});

        impact = impact.multiplyByFraction({numerator: _MIX_MAX - _MIX_VAL, denominator: _MIX_MAX})
            + argument.childsImpact.multiplyByFraction({numerator: _MIX_VAL, denominator: _MIX_MAX});
    }

    /// @notice Returns the ERC-7201 namespaced storage struct of the contract.
    /// @return arborVoteStorage The storage struct of the ArborVote contract.
    function _getArborVoteStorage() internal pure returns (ArborVoteStorage storage arborVoteStorage) {
        // solhint-disable no-inline-assembly
        // slither-disable-next-line assembly
        assembly {
            arborVoteStorage.slot := _ARBORVOTE_STORAGE_LOCATION
        }
        // solhint-enable no-inline-assembly
    }
}
