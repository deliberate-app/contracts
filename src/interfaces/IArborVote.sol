// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";

import {Argument} from "../libs/Argument.sol";
import {Phase} from "../libs/Phase.sol";
import {User} from "../libs/User.sol";

/// @title IArborVote
/// @author Michael Heuer
/// @notice The interface of the ArborVote voting module for deliberative decision-making using argument trees.
interface IArborVote {
    /// @notice Emitted when a debate is created. The thesis is the debate's root argument (ID 0).
    /// @param debateId The ID of the debate.
    /// @param creator The creator of the debate.
    /// @param contentURI The URI pointing to the content of the debate thesis.
    /// @param lockingDuration How long a new or edited argument stays a draft before it locks in.
    /// @param editingEndTime The end time of the editing phase.
    /// @param ratingEndTime The end time of the rating phase.
    event DebateCreated(
        uint256 indexed debateId,
        address indexed creator,
        bytes32 contentURI,
        uint48 lockingDuration,
        uint48 editingEndTime,
        uint48 ratingEndTime
    );

    /// @notice Emitted when a user joins a debate.
    /// @param debateId The ID of the debate.
    /// @param account The account that joined.
    /// @param tokens The vote tokens the account received.
    event Joined(uint256 indexed debateId, address indexed account, uint32 tokens);

    /// @notice Emitted when the tally completes, moving the debate into the terminal `Finished` phase.
    /// @param debateId The ID of the debate.
    /// @param approved Whether the debate approved the thesis.
    event DebateFinished(uint256 indexed debateId, bool approved);

    /// @notice Emitted when an argument is added to a debate.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param parentArgumentId The ID of the parent argument.
    /// @param creator The creator of the argument.
    /// @param isSupporting Whether the argument supports or opposes the parent argument.
    /// @param contentURI The URI pointing to the content of the argument.
    /// @param pro The pro reserve the argument's market is seeded with.
    /// @param con The con reserve the argument's market is seeded with.
    /// @param finalizationTime The time from which the argument can be finalized.
    event ArgumentAdded(
        uint256 indexed debateId,
        uint16 indexed argumentId,
        uint16 indexed parentArgumentId,
        address creator,
        bool isSupporting,
        bytes32 contentURI,
        uint32 pro,
        uint32 con,
        uint48 finalizationTime
    );

    /// @notice Emitted when an argument is moved below a new parent argument.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param newParentArgumentId The ID of the new parent argument.
    /// @param oldParentArgumentId The ID of the old parent argument.
    /// @param pro The pro reserve after re-seeding the market at the new initial approval.
    /// @param con The con reserve after re-seeding the market at the new initial approval.
    event ArgumentMoved(
        uint256 indexed debateId,
        uint16 indexed argumentId,
        uint16 indexed newParentArgumentId,
        uint16 oldParentArgumentId,
        uint32 pro,
        uint32 con
    );

    /// @notice Emitted when an argument's content is altered, which restarts its editing window.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param contentURI The URI pointing to the new content of the argument.
    /// @param finalizationTime The new time from which the argument can be finalized.
    event ArgumentAltered(
        uint256 indexed debateId, uint16 indexed argumentId, bytes32 contentURI, uint48 finalizationTime
    );

    /// @notice Emitted when a debater stakes vote tokens on one side of an argument's market.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param staker The address of the staker.
    /// @param data The data of the stake that was placed.
    event Staked(uint256 indexed debateId, uint16 indexed argumentId, address indexed staker, Argument.Stake data);

    /// @notice Emitted when a user redeems their shares in an argument after the debate finished.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param account The account whose shares were redeemed.
    /// @param proShares The pro shares redeemed.
    /// @param conShares The con shares redeemed.
    /// @param payout The vote tokens paid out for the shares.
    event SharesRedeemed(
        uint256 indexed debateId,
        uint16 indexed argumentId,
        address indexed account,
        uint32 proShares,
        uint32 conShares,
        uint32 payout
    );

    /// @notice Emitted when the impact of an argument in a debate was calculated.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param impact The impact value of the argument.
    event ArgumentImpactCalculated(uint256 indexed debateId, uint16 indexed argumentId, int64 impact);

    /// @notice Emitted when the market fees accrued by an argument are claimed for its creator.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param creator The creator of the argument the fees are credited to.
    /// @param fees The amount of vote token fees claimed.
    event FeesClaimed(uint256 indexed debateId, uint16 indexed argumentId, address indexed creator, uint32 fees);

    /// @notice Emitted when a debate's bounty pool is funded - at creation or by a later top-up.
    /// @param debateId The ID of the debate.
    /// @param funder The account the funds came from.
    /// @param token The ERC-20 the bounty is denominated in.
    /// @param amount The amount received (after any transfer fee the token takes).
    /// @param pool The bounty pool after this funding.
    event BountyFunded(
        uint256 indexed debateId, address indexed funder, IERC20 indexed token, uint256 amount, uint256 pool
    );

    /// @notice Emitted when a participant claims their bounty share.
    /// @param debateId The ID of the debate.
    /// @param account The claiming participant.
    /// @param excess The vote tokens the participant ended with beyond the initial grant.
    /// @param amount The bounty amount paid out.
    event BountyClaimed(uint256 indexed debateId, address indexed account, uint32 excess, uint256 amount);

    /// @notice Emitted when the creator sweeps the unclaimed bounty remainder after the claim window.
    /// @param debateId The ID of the debate.
    /// @param creator The debate's creator the remainder is paid to.
    /// @param amount The remainder swept.
    event BountySwept(uint256 indexed debateId, address indexed creator, uint256 amount);

    /// @notice Creates a new debate, optionally attaching an ERC-20 bounty for its net winners.
    /// @param contentURI The URI pointing to the content of the debate thesis.
    /// @param lockingDuration The time from an argument's creation (or last edit) until it locks in.
    /// @param editingDuration The length of the editing phase; longer than the locking duration, so arguments
    /// can lock in and be replied to.
    /// @param ratingDuration The length of the rating phase; at least one locking window, so every argument is
    /// final by the time the tally runs.
    /// @param bountyToken The ERC-20 the bounty is denominated in; the zero address attaches no bounty and the
    /// token cannot be changed later. Any ERC-20 works - the token is deliberately uncurated.
    /// @param bountyAmount The bounty amount to pull from the caller (requires a prior approval); may be zero
    /// to name a token and leave the funding to top-ups.
    /// @return debateId The ID of the created debate.
    function createDebate(
        bytes32 contentURI,
        uint48 lockingDuration,
        uint48 editingDuration,
        uint48 ratingDuration,
        IERC20 bountyToken,
        uint256 bountyAmount
    ) external returns (uint256 debateId);

    /// @notice Tops up a debate's bounty pool; open to anyone until the debate finishes. Top-ups are
    /// donations - they raise every claim and are not refundable.
    /// @param debateId The ID of the debate.
    /// @param amount The amount of the bounty token to pull from the caller (requires a prior approval).
    function fundBounty(uint256 debateId, uint256 amount) external;

    /// @notice Settles the caller's positions and claims their bounty share - one-shot, within the claim
    /// window. Redeems the given arguments' shares and claims their accrued creator fees first, then pays
    /// `pool * (tokens - 100) / (100 * N)` for the caller's excess over the initial grant.
    /// @param debateId The ID of the debate.
    /// @param argumentIds The arguments to settle before the claim - the caller's staked and authored ones;
    /// empty if already settled.
    function claimBounty(uint256 debateId, uint16[] calldata argumentIds) external;

    /// @notice Sweeps the unclaimed bounty remainder to the debate's creator once the claim window is over.
    /// @param debateId The ID of the debate.
    function sweepBounty(uint256 debateId) external;

    /// @notice Join a debate and receive debate tokens.
    /// @param debateId The ID of the debate.
    function join(uint256 debateId) external;

    /// @notice Adds an argument below a parent argument with a certain initial approval, staking a
    /// creator-chosen deposit that seeds the argument's market and sets its starting weight.
    /// @param debateId The ID of the debate.
    /// @param parentArgumentId The ID of the parent argument.
    /// @param contentURI The URI pointing to the argument content.
    /// @param isSupporting Whether the argument supports or opposes the parent argument.
    /// @param initialApproval The initial approval of the argument.
    /// @param deposit The vote token deposit to seed the argument's market with; at least the minimum.
    /// @return newArgumentId The ID of the created argument.
    function addArgument(
        uint256 debateId,
        uint16 parentArgumentId,
        bytes32 contentURI,
        bool isSupporting,
        uint32 initialApproval,
        uint32 deposit
    ) external returns (uint16 newArgumentId);

    /// @notice Moves an argument below a new parent argument, re-seeding its market at a new
    /// initial approval. Only a still-draft argument can move, so its reserves are still the
    /// pristine deposit split and re-seeding them is lossless; pass the current approval to
    /// keep the rating unchanged.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to be moved.
    /// @param newParentArgumentId The ID of the new parent argument.
    /// @param initialApproval The initial approval to re-seed the argument's market at.
    function moveArgument(uint256 debateId, uint16 argumentId, uint16 newParentArgumentId, uint32 initialApproval)
        external;

    /// @notice Alters the content of an argument.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to be altered.
    /// @param contentURI The URI pointing to the argument content.
    function alterArgument(uint256 debateId, uint16 argumentId, bytes32 contentURI) external;

    /// @notice Stakes an amount of vote tokens on the pro side, buying pro shares.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to stake on.
    /// @param voteTokenAmount The amount of vote tokens to be staked.
    function stakePro(uint256 debateId, uint16 argumentId, uint32 voteTokenAmount) external;

    /// @notice Stakes an amount of vote tokens on the con side, buying con shares.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to stake on.
    /// @param voteTokenAmount The amount of vote tokens to be staked.
    function stakeCon(uint256 debateId, uint16 argumentId, uint32 voteTokenAmount) external;

    /// @notice Tallies the argument tree of a debate.
    /// @param debateId The ID of the debate.
    function tallyTree(uint256 debateId) external;

    /// @notice Redeems the shares a user holds in an argument of a debate for vote tokens.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param account The account to redeem the shares for.
    function redeemArgumentShares(uint256 debateId, uint16 argumentId, address account) external;

    /// @notice Redeems the shares a user holds across several arguments of a debate in one call.
    /// Arguments the account holds no shares in are skipped, so a stale ID is harmless.
    /// @param debateId The ID of the debate.
    /// @param argumentIds The IDs of the arguments to redeem shares in.
    /// @param account The account to redeem the shares for.
    function redeemArgumentSharesBatch(uint256 debateId, uint16[] calldata argumentIds, address account) external;

    /// @notice Claims the market fees accrued by an argument's market, crediting them to the argument's creator.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    function claimFees(uint256 debateId, uint16 argumentId) external;

    /// @notice Returns an argument from a debate.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @return argument The argument queried.
    function getArgument(uint256 debateId, uint16 argumentId) external view returns (Argument.Data memory argument);

    /// @notice Returns the leaf argument IDs of a debate.
    /// @param debateId The ID of the debate.
    /// @return leafArgumentIds The leaf argument IDs.
    function getLeafArgumentIds(uint256 debateId) external view returns (uint16[] memory leafArgumentIds);

    /// @notice Returns the role of a user in a debate.
    /// @param debateId The ID of the debate.
    /// @param account The account of the user.
    /// @return role The user role.
    function getUserRole(uint256 debateId, address account) external view returns (User.Role role);

    /// @notice Returns the tokens of a user in a debate.
    /// @param debateId The ID of the debate.
    /// @param account The account of the user.
    /// @return tokens The user tokens.
    function getUserTokens(uint256 debateId, address account) external view returns (uint32 tokens);

    /// @notice Returns the shares of a user of an argument in a debate.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param account The account of the user.
    /// @return shares The user shares.
    function getUserShares(uint256 debateId, uint16 argumentId, address account)
        external
        view
        returns (User.Shares memory shares);

    /// @notice Returns the number of debates created so far; debate IDs run from 0 to `count - 1`.
    /// @return count The number of created debates.
    function debatesCount() external view returns (uint256 count);

    /// @notice Returns the aggregate data of a debate.
    /// @param debateId The ID of the debate.
    /// @return totalVotes The total votes cast in the debate.
    /// @return argumentsCount The number of arguments in the debate.
    /// @return participantsCount The number of accounts that joined the debate.
    function debates(uint256 debateId)
        external
        view
        returns (uint32 totalVotes, uint16 argumentsCount, uint32 participantsCount);

    /// @notice Returns the bounty state of a debate.
    /// @param debateId The ID of the debate.
    /// @return token The ERC-20 the bounty is denominated in; the zero address means no bounty.
    /// @return pool The total amount funded.
    /// @return claimed The total amount paid out to claimants so far.
    /// @return swept Whether the creator has swept the remainder.
    /// @return claimEndTime The time the claim window closes; zero while the debate is unfinished.
    function bounty(uint256 debateId)
        external
        view
        returns (IERC20 token, uint256 pool, uint256 claimed, bool swept, uint48 claimEndTime);

    /// @notice Returns the role, tokens, and bounty claim state of a user in a debate.
    /// @param debateId The ID of the debate.
    /// @param account The account of the user.
    /// @return role The role of the user.
    /// @return tokens The vote token balance of the user.
    /// @return bountyClaimed Whether the user has claimed their bounty share (claims are one-shot).
    function users(uint256 debateId, address account)
        external
        view
        returns (User.Role role, uint32 tokens, bool bountyClaimed);

    /// @notice Returns the phase data of a debate.
    /// @param debateId The ID of the debate.
    /// @return currentPhase The current phase of the debate.
    /// @return editingEndTime The end time of the editing phase.
    /// @return ratingEndTime The end time of the rating phase.
    /// @return lockingDuration The debate's locking duration.
    function phases(uint256 debateId)
        external
        view
        returns (Phase.Status currentPhase, uint48 editingEndTime, uint48 ratingEndTime, uint48 lockingDuration);

    /// @notice Returns the outcome of the debate.
    /// @param debateId The ID of the debate.
    /// @return approved Whether the debate approved the root thesis or not.
    function outcome(uint256 debateId) external view returns (bool approved);

    /// @notice Quotes a stake on one side of an argument's market: the fee and the shares
    /// the staker would receive under constant-product pricing.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to stake on.
    /// @param isPro Whether the stake buys pro or con shares.
    /// @param voteTokenAmount The amount of vote tokens to be staked.
    /// @return stakeData The container holding the quoted amounts.
    function quoteStake(uint256 debateId, uint16 argumentId, bool isPro, uint32 voteTokenAmount)
        external
        view
        returns (Argument.Stake memory stakeData);
}
