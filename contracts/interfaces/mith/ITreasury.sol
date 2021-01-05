pragma solidity >=0.6.2;

interface ITreasury {
    function allocateSeigniorage() external;

    function nextEpochPoint() external view returns (uint256);
    function getCurrentEpoch() external view returns (uint256);
    function getLastAllocated() external view returns (uint256);

    function startTime() external view returns (uint256);
}
