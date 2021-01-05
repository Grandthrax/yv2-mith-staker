pragma solidity >=0.6.2;

interface IBoardroom {
    function balanceOf(address account) external view returns (uint256);

    function getShareOf(address account) external view returns (uint256);

    function allocateSeigniorage(uint256 amount) external;

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function exit() external;

    function claimReward() external;
}
