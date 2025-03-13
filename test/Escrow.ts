import {
	time,
	loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import { ethers } from "ethers";

describe("Escrow", function () {
	async function deployEscrow() {
		const TWO_WEEKS_IN_SECONDS = 365 * 24 * 60 * 60;
		const ONE_GWEI = ethers.toBigInt(1e15);

		const lockedAmount = 10n ** 16n;
		const deadline = (await time.latest()) + TWO_WEEKS_IN_SECONDS;
		const daoDeadline = deadline + TWO_WEEKS_IN_SECONDS;

		// Contracts are deployed using the first signer/account by default
		const [owner, payer, payee] = await hre.ethers.getSigners();

		const Escrow = await hre.ethers.getContractFactory("HyperBoreEscrow");
		const escrow = await Escrow.deploy(owner.address);

		return { escrow, deadline, daoDeadline, lockedAmount, owner, payer, payee };
	}

	describe("Deployment", function () {
		it("Should set the right multisig", async function () {
			const { escrow, owner } = await loadFixture(deployEscrow);

			expect(await escrow.daoMultisig()).to.equal(owner.address);
		});
	});

	describe("Escrow", function () {
		describe("Creating Escrow", function () {
			it("Should revert if invalid payee address entered", async function () {
				const { escrow, payer, lockedAmount, deadline, daoDeadline } =
					await loadFixture(deployEscrow);
				await expect(
					escrow
						.connect(payer)
						.createEscrow(
							"0x0000000000000000000000000000000000000000",
							"0x0000000000000000000000000000000000000000",
							lockedAmount,
							deadline,
							daoDeadline,
							{ value: lockedAmount }
						)
				).to.be.revertedWith("Invalid payee address");
			});

			it("Should create escrow successfully", async function () {
				const { escrow, payer, payee, lockedAmount, deadline, daoDeadline } =
					await loadFixture(deployEscrow);
				await expect(
					escrow
						.connect(payer)
						.createEscrow(
							payee.address,
							"0x0000000000000000000000000000000000000000",
							lockedAmount,
							deadline,
							daoDeadline,
							{ value: lockedAmount }
						)
				)
					.to.emit(escrow, "EscrowCreated")
					.withArgs(
						anyValue,
						payer.address,
						payee.address,
						lockedAmount,
						"0x0000000000000000000000000000000000000000"
					);
			});

			it("Should be reverted if the payment is too small", async function () {
				const { escrow, payer, payee, lockedAmount, deadline, daoDeadline } =
					await loadFixture(deployEscrow);
				await expect(
					escrow
						.connect(payer)
						.createEscrow(
							payee.address,
							"0x0000000000000000000000000000000000000000",
							lockedAmount / 10n,
							deadline,
							daoDeadline,
							{ value: lockedAmount / 10n }
						)
				).to.be.revertedWith("Escrow amount too small");
			});
		});
	});
});
