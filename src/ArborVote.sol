// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin-contracts-5.6.1/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-5.6.1/proxy/utils/UUPSUpgradeable.sol";
import {Time} from "@openzeppelin-contracts-5.6.1/utils/types/Time.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/access/OwnableUpgradeable.sol";

import {IArborVote} from "./interfaces/IArborVote.sol";
import {IProofOfHumanity} from "./interfaces/IProofOfHumanity.sol";
import {Argument} from "./libs/Argument.sol";
import {Debate} from "./libs/Debate.sol";
import {Phase} from "./libs/Phase.sol";
import {User} from "./libs/User.sol";
import {Utils} from "./libs/Utils.sol";

/// @title ArborVote
/// @author Michael Heuer
/// @notice A voting module for deliberative decision-making using argument trees. The contract is a conventional UUPS
/// upgradeable contract owned via OpenZeppelin's `OwnableUpgradeable` and using ERC-7201 namespaced storage.
contract ArborVote is IArborVote, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using Utils for uint16[];
    using Utils for uint32;
    using Utils for uint64;
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

    /// @notice Disables the initializers on the implementation contract to prevent it from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IArborVote
    function initialize(IProofOfHumanity poh) external override initializer {
        __Ownable_init(msg.sender);
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
    function moveArgument(uint256 debateId, uint16 argumentId, uint16 newParentArgumentId)
        external
        override
        onlyPhase(debateId, Phase.Status.Editing)
        onlyCreator(debateId, argumentId)
        onlyArgumentState(debateId, argumentId, Argument.State.Created)
    {
        Debate.Data storage debate = _getArborVoteStorage().debates[debateId];
        Argument.Data storage movedArgument = debate.arguments[argumentId];

        // change old parent's argument state
        uint16 oldParentArgumentId = movedArgument.parentArgumentId;
        _updateParentAfterChildRemoval({debateId: debateId, parentArgumentId: oldParentArgumentId});

        // change argument state
        movedArgument.parentArgumentId = newParentArgumentId;

        // change new parent argument state
        debate.arguments[newParentArgumentId].untalliedChilds++;

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
    {
        User.Data storage user = _getArborVoteStorage().users[debateId][msg.sender];

        if (user.tokens < voteTokenAmount) {
            revert InsufficientVoteTokens({required: voteTokenAmount, actual: user.tokens});
        }

        user.tokens -= voteTokenAmount;

        Argument.Investment memory data =
            calculateInvestment({debateId: debateId, argumentId: argumentId, voteTokenAmount: voteTokenAmount});
        data.conSwap = 0;

        _executeProInvestment({debateId: debateId, argumentId: argumentId, investment: data});

        user.shares[argumentId].pro += data.proMint + data.proSwap;

        emit Invested({debateId: debateId, argumentId: argumentId, investor: msg.sender, data: data});
    }

    /// @inheritdoc IArborVote
    function investInCon(uint256 debateId, uint16 argumentId, uint32 voteTokenAmount)
        external
        override
        onlyPhase(debateId, Phase.Status.Rating)
    {
        User.Data storage user = _getArborVoteStorage().users[debateId][msg.sender];

        if (user.tokens < voteTokenAmount) {
            revert InsufficientVoteTokens({required: voteTokenAmount, actual: user.tokens});
        }

        user.tokens -= voteTokenAmount;

        Argument.Investment memory data =
            calculateInvestment({debateId: debateId, argumentId: argumentId, voteTokenAmount: voteTokenAmount});
        data.proSwap = 0;

        _executeConInvestment({debateId: debateId, argumentId: argumentId, investment: data});

        user.shares[argumentId].con += data.conMint + data.conSwap;

        emit Invested({debateId: debateId, argumentId: argumentId, investor: msg.sender, data: data});
    }

    /// @inheritdoc IArborVote
    function tallyTree(uint256 debateId) external override onlyPhase(debateId, Phase.Status.Tallying) {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        uint16[] memory leafArgumentIds = $.debates[debateId].leafArgumentIds;

        uint256 arrayLength = leafArgumentIds.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            _tallyNode(debateId, leafArgumentIds[i]);
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

        /**
         * def y_share(self, y_amount):
         *     return y_amount / (self.__y + self.__y_issued)
         * def returns_y_in_b(self, y_amount):
         *     b_share = self.__b * self.approval()
         *     return self.y_share(y_amount) * b_share
         */
        if (userShares.pro > 0) {
            user.tokens += argument.votes
                .multiplyByFraction(
                    argument.con * userShares.pro, (argument.pro + argument.con) * (argument.pro + argument.proIssued)
                );
            userShares.pro = 0;
        }

        /**
         * def n_share(self, n_amount):
         *     return n_amount / (self.__n + self.__n_issued)
         * def returns_n_in_b(self, n_amount):
         *     b_share = self.__b * self.disapproval()
         *     return self.n_share(n_amount) * b_share
         */
        if (userShares.con > 0) {
            user.tokens += argument.votes
                .multiplyByFraction(
                    argument.pro * userShares.con, (argument.pro + argument.con) * (argument.con + argument.conIssued)
                );
            userShares.con = 0;
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
        return _getArborVoteStorage().debates[debateId].leafArgumentIds;
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
        onlyRole(debateId, User.Role.Participant)
        onlyArgumentState(debateId, parentArgumentId, Argument.State.Final)
        returns (uint16 newArgumentId)
    {
        ArborVoteStorage storage $ = _getArborVoteStorage();

        User.Data storage user = $.users[debateId][msg.sender];

        if (initialApproval < 50) {
            revert InitialApprovalOutOfBounds({limit: 50, actual: initialApproval});
        }
        if (initialApproval > 100) {
            revert InitialApprovalOutOfBounds({limit: 100, actual: initialApproval});
        }

        if (user.tokens < _DEBATE_DEPOSIT) {
            revert InsufficientVoteTokens({required: _DEBATE_DEPOSIT, actual: user.tokens});
        }

        // initialize market
        Debate.Data storage debate = $.debates[debateId];

        user.tokens -= _DEBATE_DEPOSIT;

        // Create new argument
        newArgumentId = _createArgument({
            debateId: debateId,
            parentArgumentId: parentArgumentId,
            contentURI: contentURI,
            isSupporting: isSupporting,
            initialApproval: initialApproval
        });

        // Update parent
        debate.arguments[parentArgumentId].untalliedChilds++;

        // Update the debate's leaf arguments if this is not the root argument
        if (parentArgumentId != 0) {
            debate.leafArgumentIds.removeByValue({value: parentArgumentId});
        }
        debate.leafArgumentIds.push(newArgumentId);

        emit ArgumentUpdated({
            debateId: debateId, argumentId: newArgumentId, parentArgumentId: parentArgumentId, contentURI: contentURI
        });
    }

    /// @inheritdoc IArborVote
    function calculateInvestment(uint256 debateId, uint16 argumentId, uint32 voteTokenAmount)
        public
        view
        override
        returns (Argument.Investment memory investmentData)
    {
        investmentData.voteTokensInvested = voteTokenAmount;

        Argument.Data storage argument = _getArborVoteStorage().debates[debateId].arguments[argumentId];

        investmentData.fee = voteTokenAmount.multiplyByFraction({numerator: _FEE_PERCENTAGE, denominator: 100});
        (uint32 proMint, uint32 conMint) = (voteTokenAmount - investmentData.fee).split(argument.pro, argument.con);

        investmentData.proMint = proMint;
        investmentData.conMint = conMint;

        investmentData.proSwap = _calculateProSwap({proMint: proMint, conMint: conMint});
        investmentData.conSwap = _calculateConSwap({proMint: proMint, conMint: conMint});
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

        // Seed the argument market with the deposit at the creator's initial approval (pro share percentage).
        (argument.pro, argument.con) = _DEBATE_DEPOSIT.split(initialApproval, 100 - initialApproval);
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

        // Eventually, the parent argument becomes a leaf after the removal
        if (parentArgument.untalliedChilds == 0) {
            // append
            debate.leafArgumentIds.push(parentArgumentId);
        }
    }

    /// @notice Internal function to execute an investment to obtain pro tokens on the argument's market in a debate.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to invest in.
    /// @param investment The container containing the investment data.
    function _executeProInvestment(uint256 debateId, uint16 argumentId, Argument.Investment memory investment)
        internal
    {
        uint32 votes = investment.voteTokensInvested - investment.fee;

        Debate.Data storage debate = _getArborVoteStorage().debates[debateId];
        Argument.Data storage argument = debate.arguments[argumentId];

        debate.totalVotes += votes;
        debate.arguments[argument.parentArgumentId].childsVote += votes;

        argument.votes += votes;
        argument.fees += investment.fee;
        argument.pro -= investment.proSwap;
        argument.proIssued += investment.proMint + investment.proSwap;
        argument.con += investment.conMint;
    }

    /// @notice Internal function to execute an investment to obtain con tokens on the argument's market in a debate.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to invest in.
    /// @param investment The container containing the investment data.
    function _executeConInvestment(uint256 debateId, uint16 argumentId, Argument.Investment memory investment)
        internal
    {
        uint32 votes = investment.voteTokensInvested - investment.fee;

        Debate.Data storage debate = _getArborVoteStorage().debates[debateId];
        Argument.Data storage argument = debate.arguments[argumentId];

        debate.totalVotes += votes;
        debate.arguments[argument.parentArgumentId].childsVote += votes;

        argument.votes += votes;
        argument.fees += investment.fee;
        argument.pro += investment.proMint;
        argument.con -= investment.conSwap;
        argument.conIssued += investment.conMint + investment.conSwap;
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

        // Calculate own impact $r_j$
        int64 ownImpact = _calculateImpact({debateId: debateId, argumentId: argumentId});

        // Apply pre-factor $\sigma_j$
        if (!argument.isSupporting) {
            ownImpact = -ownImpact;
        }

        // Apply weight $w_j$. The parent holds the summed votes of all its children (the siblings).
        ownImpact = ownImpact.multiplyByFraction({numerator: argument.votes, denominator: parentArgument.childsVote});

        // Update the parent argument impact
        parentArgument.childsImpact += ownImpact;
        parentArgument.untalliedChilds--;

        // if all childs of the parent are tallied, tally parent
        if (parentArgument.untalliedChilds == 0) {
            _tallyNode({debateId: debateId, argumentId: parentArgumentId});
        }

        emit ArgumentImpactCalculated({debateId: debateId, argumentId: argumentId, impact: ownImpact});
    }

    /// @notice Authorizes an upgrade of the contract via the UUPS proxy pattern.
    /// @dev The caller must be the owner of the contract.
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner {}

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

        // calculate own impact
        impact = _MAX_APPROVAL.multiplyByFraction({numerator: pro, denominator: pro + con});

        impact = impact.multiplyByFraction({numerator: _MIX_MAX - _MIX_VAL, denominator: _MIX_MAX})
            + argument.childsImpact.multiplyByFraction({numerator: _MIX_VAL, denominator: _MIX_MAX});
    }

    /// @notice Internal function to calculate the amount of pro tokens obtained from swapping the minted con tokens.
    /// @param proMint The amount of pro tokens.
    /// @param conMint The amount of con tokens.
    /// @return proSwap The amount of pro tokens obtained from swapping the minted con tokens.
    function _calculateProSwap(uint32 proMint, uint32 conMint) internal pure returns (uint32 proSwap) {
        (conMint);
        return proMint - proMint / 2;
    }

    /// @notice Internal function to calculate the amount of con tokens obtained from swapping the minted pro tokens.
    /// @param proMint The amount of pro tokens.
    /// @param conMint The amount of con tokens.
    /// @return conSwap The amount of con tokens obtained from swapping the minted pro tokens.
    function _calculateConSwap(uint32 proMint, uint32 conMint) internal pure returns (uint32 conSwap) {
        conSwap = proMint - proMint / (1 + proMint / conMint); // TODO Revisit formulas
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
