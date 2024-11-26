import datetime
from decimal import Decimal, getcontext

# Set the precision for Decimal calculations
getcontext().prec = 30

class Stake:
    def __init__(self, owner, amount, multiplier):
        self.owner = owner
        self.amount = Decimal(amount)
        self.multiplier = Decimal(multiplier)
        self.rewards = Decimal('0')

class StakingSystem:
    def __init__(self, daily_budget):
        self.stakes = []
        self.daily_budget = Decimal(daily_budget)
        self.total_ponderated_stake = Decimal('0')
        self.current_date = datetime.date(2024, 1, 1)  # Starting date

    def add_stake(self, owner, amount, multiplier):
        stake = Stake(owner, Decimal(amount), Decimal(multiplier))
        self.stakes.append(stake)
        self.total_ponderated_stake += stake.amount * stake.multiplier

    def unstake(self, owner, stake_index):
        stakes_by_owner = [s for s in self.stakes if s.owner == owner]
        if 0 <= stake_index < len(stakes_by_owner):
            stake = stakes_by_owner[stake_index]
            self.total_ponderated_stake -= stake.amount * stake.multiplier
            total_return = stake.amount + stake.rewards
            self.stakes.remove(stake)
            return total_return
        return Decimal('0')

    def calculate_rewards(self):
        for stake in self.stakes:
            reward = stake.amount * self.daily_budget * stake.multiplier / self.total_ponderated_stake
            if stake.multiplier == 1:
                stake.rewards += reward
            else:
                stake.amount += reward
        self.update_total_ponderated_stake()

    def update_total_ponderated_stake(self):
        self.total_ponderated_stake = sum(stake.amount * stake.multiplier for stake in self.stakes)

    def simulate_day(self):
        self.calculate_rewards()
        self.current_date += datetime.timedelta(days=1)

    def print_status(self, fullStatus=False):
        if fullStatus:
            print(f"Date: {self.current_date}")
            for stake in self.stakes:
                if stake.multiplier == 1:
                    print(f"{stake.owner}: {stake.amount+stake.rewards:,.4f} = {stake.amount:,.4f} (x1) + {stake.rewards:,.2f}")
                else:
                    print(f"{stake.owner}: {stake.amount:,.4f} (x{stake.multiplier})")
            print(f"Total ponderated Stake: {self.total_ponderated_stake:,.4f}")
            print("--------------------")
        else:
            print(f"{int(self.total_ponderated_stake):.3f}")  # Rounded down total ponderated stake

# Simulation
system = StakingSystem(daily_budget=624657534246.0)

# Day 1
system.add_stake("Bob", Decimal('1000.0e8'), Decimal('1.6'))

# Day 2
system.simulate_day()
system.add_stake("Alice", Decimal('150.0e8'), Decimal('1'))

# Day 5
system.simulate_day()
system.simulate_day()
system.simulate_day()
system.add_stake("Bob", Decimal('1000.0e8'), Decimal('1.3'))

# Day 9
for _ in range(4):
    system.simulate_day()

# Day 10
system.simulate_day()
system.add_stake("Charlie", Decimal('10000.0e8'), Decimal('3'))

# Day 22
for _ in range(12):
    system.simulate_day()

# Day 23
system.simulate_day()
system.print_status(True)
unstaked_amount = system.unstake("Alice", 0)

# Day 95
for _ in range(72):
    system.simulate_day()

# Day 96
system.simulate_day()
system.print_status(True)
unstaked_amount = system.unstake("Bob", 1)

# Day 107
for _ in range(11):
    system.simulate_day()

# Day 108
system.simulate_day()
system.add_stake("Alice", Decimal('1000.0e8'), Decimal('2.2'))

# Day 195
for _ in range(87):
    system.simulate_day()

# Day 196
system.simulate_day()
system.print_status(True)
unstaked_amount = system.unstake("Bob", 0)

# Day 201
for _ in range(5):
    system.simulate_day()
system.print_status(True)

# Day 601
for _ in range(400):
    system.simulate_day()
system.print_status(True)

# Day 1200
for _ in range(599):
    system.simulate_day()

system.simulate_day()
system.print_status(True)