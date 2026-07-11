// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Argument} from "../libs/Argument.sol";
import {Phase} from "../libs/Phase.sol";
import {User} from "../libs/User.sol";

/// @title IArborVote
/// @author Michael Heuer
/// @notice The interface of the ArborVote voting module for deliberative decision-making using argument trees.
interface IArborVote {
    /// @notice Emitted when an argument in a debate is updated.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param parentArgumentId The ID of the parent argument.
    /// @param contentURI The URI pointing to the content of the argument.
    event ArgumentUpdated(
        uint256 indexed debateId, uint16 indexed argumentId, uint16 indexed parentArgumentId, bytes32 contentURI
    );

    /// @notice Emitted when a debater invests vote tokens in an argument in a debate.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param investor The address of the investor.
    /// @param data The data of the investment that was made.
    event Invested(
        uint256 indexed debateId, uint16 indexed argumentId, address indexed investor, Argument.Investment data
    );

    /// @notice Emitted when the impact of an argument in a debate was calculated.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param impact The impact value of the argument.
    event ArgumentImpactCalculated(uint256 indexed debateId, uint16 indexed argumentId, int64 impact);

    /// @notice Emitted when the investment fees accrued by an argument are claimed for its creator.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param creator The creator of the argument the fees are credited to.
    /// @param fees The amount of vote token fees claimed.
    event FeesClaimed(uint256 indexed debateId, uint16 indexed argumentId, address indexed creator, uint32 fees);

    /// @notice Creates a new debate.
    /// @param contentURI The URI pointing to the content of the debate thesis.
    /// @param timeUnit The time unit of the debate determining the editing and rating durations.
    /// @return debateId The ID of the created debate.
    function createDebate(bytes32 contentURI, uint48 timeUnit) external returns (uint256 debateId);

    /// @notice Advances the phase of the debate.
    /// @param debateId The ID of the debate.
    function advancePhase(uint256 debateId) external;

    /// @notice Join a debate and receive debate tokens.
    /// @param debateId The ID of the debate.
    function join(uint256 debateId) external;

    /// @notice Finalizes an argument of a debate.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to be finalized.
    function finalizeArgument(uint256 debateId, uint16 argumentId) external;

    /// @notice Adds an argument below a parent argument with a certain initial approval.
    /// @param debateId The ID of the debate.
    /// @param parentArgumentId The ID of the parent argument.
    /// @param contentURI The URI pointing to the argument content.
    /// @param isSupporting Whether the argument supports or opposes the parent argument.
    /// @param initialApproval The initial approval of the argument.
    /// @return newArgumentId The ID of the created argument.
    function addArgument(
        uint256 debateId,
        uint16 parentArgumentId,
        bytes32 contentURI,
        bool isSupporting,
        uint32 initialApproval
    ) external returns (uint16 newArgumentId);

    /// @notice Moves an argument below a new parent argument.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to be moved.
    /// @param newParentArgumentId The ID of the new parent argument.
    function moveArgument(uint256 debateId, uint16 argumentId, uint16 newParentArgumentId) external;

    /// @notice Alters the content of an argument.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to be altered.
    /// @param contentURI The URI pointing to the argument content.
    function alterArgument(uint256 debateId, uint16 argumentId, bytes32 contentURI) external;

    /// @notice Invests an amount of vote tokens into pro shares.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to invest in.
    /// @param voteTokenAmount The amount of vote tokens to be invested.
    function investInPro(uint256 debateId, uint16 argumentId, uint32 voteTokenAmount) external;

    /// @notice Invests an amount of vote tokens into con shares.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to invest in.
    /// @param voteTokenAmount The amount of vote tokens to be invested.
    function investInCon(uint256 debateId, uint16 argumentId, uint32 voteTokenAmount) external;

    /// @notice Tallies the argument tree of a debate.
    /// @param debateId The ID of the debate.
    function tallyTree(uint256 debateId) external;

    /// @notice Redeems the shares a user holds in an argument of a debate for vote tokens.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument.
    /// @param account The account to redeem the shares for.
    function redeemArgumentShares(uint256 debateId, uint16 argumentId, address account) external;

    /// @notice Claims the investment fees accrued by an argument's market, crediting them to the argument's creator.
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

    /// @notice Returns the aggregate data of a debate.
    /// @param debateId The ID of the debate.
    /// @return totalVotes The total votes cast in the debate.
    /// @return argumentsCount The number of arguments in the debate.
    function debates(uint256 debateId) external view returns (uint32 totalVotes, uint16 argumentsCount);

    /// @notice Returns the role and tokens of a user in a debate.
    /// @param debateId The ID of the debate.
    /// @param account The account of the user.
    /// @return role The role of the user.
    /// @return tokens The vote token balance of the user.
    function users(uint256 debateId, address account) external view returns (User.Role role, uint32 tokens);

    /// @notice Returns the phase data of a debate.
    /// @param debateId The ID of the debate.
    /// @return currentPhase The current phase of the debate.
    /// @return editingEndTime The end time of the editing phase.
    /// @return ratingEndTime The end time of the rating phase.
    /// @return timeUnit The time unit of the debate.
    function phases(uint256 debateId)
        external
        view
        returns (Phase.Status currentPhase, uint48 editingEndTime, uint48 ratingEndTime, uint48 timeUnit);

    /// @notice Returns the outcome of the debate.
    /// @param debateId The ID of the debate.
    /// @return approved Whether the debate approved the root thesis or not.
    function outcome(uint256 debateId) external view returns (bool approved);

    /// @notice Calculates the amounts of mintable and swapable pro and con shares to be returned for an amount of vote
    /// token to be invested.
    /// @param debateId The ID of the debate.
    /// @param argumentId The ID of the argument to invest in.
    /// @param voteTokenAmount The amount of vote tokens to be invested.
    /// @return investmentData The container containing the calculated amounts.
    function calculateInvestment(uint256 debateId, uint16 argumentId, uint32 voteTokenAmount)
        external
        view
        returns (Argument.Investment memory investmentData);
}
