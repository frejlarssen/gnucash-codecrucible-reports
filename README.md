# Reports for GnuCash customized for CodeCrucible

* [Motivation](#motivation)
* [GnuCash](#gnucash)
* [Installation](#installation)
* [The reports](#the-reports)

## Motivation

Before installing you might wonder why you should do it. This section explains why.

Accounts in GnuCash are organized in an account tree. The accounts for expenses might for example be organized like this:

<figure>
    <img src="images/simple_expenses.png"
         alt="Simple expenses example">
    <figcaption>Figure 1: Expenses.</figcaption>
</figure>

CodeCrucible runs multiple programs, for example one in August 2025 and one in December 2025. We would like to seperate the expenses between these programs. One **bad** way to do this would be:

<figure>
    <img src="images/bad_expenses.png"
         alt="Bad expenses example">
    <figcaption>Figure 2: Bad example.</figcaption>
</figure>

Instead, we want to organize the account tree as in Figure 1. We differ between projects when we do transactions by "tagging" them in the description:

<figure>
    <img src="images/transactions.png"
         alt="Transactions">
    <figcaption>Figure 3: Transactions with tags for accounts.</figcaption>
</figure>

The reports in this file allows us to use these tags to see total expenses for the program `#P-2025Aug` (August holiday 2025) etc.

## GnuCash

Make sure you download [GnuCash](https://gnucash.org) and learn the basics, for example using the tutorial.

This is repository contains custom reports for GnuCash 5, customized for CodeCrucible.

The reports are:

* Transaction Report Extended (`transaction-extended.scm`)

* Project Balance (`project-tags-balance.scm`)

(More fancy ones will be added later. (Pie-charts etc would be cool.))

## Installation

The commands in this guide assumes you are using Linux, but the steps for other operating systems should be similar.

### Step 1. Clone this repository

Either clone the repository or download the zip and unzip the folder in some working directory.

![Screenshot of how to clone](images/clone.png)

Enter the repository with

```bash
cd gnucash-codecrucible-reports
```

### Step 2. Setup using setup file

Give yourself permission to execute `setup.sh`:

```bash
chmod u+x setup.sh
```

Run the file `setup.sh`:

```bash
./setup.sh
```

If this didn't work, do it manually following [these](./docs/manual-setup.md) steps.

### Step 3. Restart GnuCash

After restarting GnuCash, the custom "Transaction Report Extended" should be available under the Reports - Experimental menu.

Open the options and select accounts and date similar to the normal transaction report. It should show totals per program by default. For more configuration, check below.

## The reports

### Transaction Report Extended

**Filename**: transaction-extended.scm

**Description**: Similar to the built in Transaction Report, but also has the capability to sort by project (#P- tag).

### Project Balance

**Filename**: project-tags-balance.scm

**Description**: Shows an overview over all projects. It shows the Incomes, Expenses, Reallocations between projects and the projects balance (Income - Expenses + Reallocations in - Reallocations out).

This report expects two accounts `Income:Project Reallocations` and `Expenses:Project Reallocations`. Add them like you would add any account. Right click on the `Income` account and fill in:

<figure>
    <img src="images/project_reallocations.png"
         alt="Project Reallocations">
    <figcaption>Figure 4: Adding Project reallocations to Income.</figcaption>
</figure>

Do the same for `Expenses`.

For example, if the project #P-2025Aug has 0 incomes and 3000 ksh expenses, it's balance would be -3000. When the #P-2025Aug program is over, we must therefore reallocate 3000 ksh from #P-general to #P-2025Aug, to make the balance 0.

<figure>
    <img src="images/reallocation_transaction.png"
         alt="3000 ksh from #P-general to #P-2025Aug.">
    <figcaption>Figure 5: 3000 ksh from #P-general to #P-2025Aug.</figcaption>
</figure>

The Project Balance report now looks like this:

<figure>
    <img src="images/project_balance_report.png"
         alt="3000 ksh from #P-general to #P-2025Aug.">
    <figcaption>Figure 6: #P-2025Aug is cleared.</figcaption>
</figure>

## Report Features

Disclaimer: Some of this is from the repository I forked, so it might not be up to date./Frej

### Transaction Report Extended

**Description**: Based on the built-in transaction report, it provides these additional features:
+ a Sort by Substring option which includes a regular expression match similar to the one offered for the transaction filter. That feature is the generic version of the Transaction Report with Tags.
+ a new option on the display tab called "Use More Permissive Match for Other Account Name and Code". This option enables a more permissive match for the other account name and code in order to reduce the number of "split transaction" account names with multisplits.

(TO DO. But it basically works similar to "Transaction Report with Tags", but with capability of searching for any string.)

### Transaction Report with Tags

A new tags sort key is made available in the primary and secondary key drop-down list, in the sorting options.

![image](https://github.com/Gnucash/gnucash/assets/267163/89f11c52-5a88-44ad-be61-605c5ec2271e)

To see the transactions grouped by tags, one should select that key as well as enable the subtotal for the level selected.

More options are made available at the bottom of the sorting options.

![image](https://github.com/Gnucash/gnucash/assets/267163/d7adf39d-751b-4a2c-b8de-a8cefd8c3f83)

#### Tag Prefix

- By default, the sort engine will look for tags starting with #. However to accomodate the ability to tag multiple dimensions (meaning several tags per transaction), the user is able to change that prefix to any character (even the # could be changed). For instance you could use tags for a project dimension, for instance #P-XXX where XXX is your project reference, so #P-001 #P-002 etc. You could also use tags for different departments so #D for instance, #D-MKTING #D-FINANCE, etc. Then to run a report on the project dimension, set the tag to #P, for the department dimension set the tag to #D. 
- A checkbox allows to select the option to remove the prefix from the subtotal heading, so #D-FINANCE would simply show as FINANCE as the heading for instance (assuming #D- is entered as prefix)
- The tag search is first applied to the split memo, then if no match the transaction notes, then if no match the transaction description. Only the first matched tag (as per the prefix) is considered.

#### No-Match Heading
This is the heading that will be used for the subtotal group listing transactions with no match. A checkbox allows to automatically add the prefix to it or not.

#### Examples
Here is an example of a report sorted with the defaults on first level. Second level is sorted by account. I am using 2 tags in this sample file: #P-Anna and #P-Bob. Untagged transactions are listed at the bottom in the No Match # section.
![image](https://user-images.githubusercontent.com/267163/235810080-d1ddeb62-291d-42f5-bda2-a32c71fcb69a.png)
![image](https://user-images.githubusercontent.com/267163/235810114-5abecc03-6c4f-4b05-b7eb-bee49d67e549.png)

Here is an example where I change the headings with these options.
![image](https://github.com/Gnucash/gnucash/assets/267163/e60027cd-d543-4ed7-b0a2-26448e161036)

Now my headings are a cleaner Anna, Bob and Nobody.
![image](https://user-images.githubusercontent.com/267163/235810285-6ecd1fda-675a-45ba-943c-be07810fb308.png)
![image](https://user-images.githubusercontent.com/267163/235810305-b187e3c1-5990-4c9f-a09a-fd0664e839dd.png)

It is possible to remove the transactions with no matching tags by using the existing transaction filter (filter tab). Simply put the same tag prefix (# or whatever else you are using) in the Transaction Filter field.
![image](https://github.com/dawansv/gnucash-transaction-tags/assets/267163/cf5dc927-9534-46db-aa2c-c1bd88e47f79)

Here only Anna and Bob are listed. No-match "Nobody" is no longer there.
![image](https://user-images.githubusercontent.com/267163/235810480-de731104-ab48-4f30-a4dd-6257ef9f7f96.png)

Now I only want to see unmatched transactions.
![image](https://github.com/dawansv/gnucash-transaction-tags/assets/267163/2da6ae6c-2631-47a8-b92b-b4ea0f803945)

These are just transactions that are not assigned to anybody
![image](https://user-images.githubusercontent.com/267163/235812541-32044a35-a32a-46ee-9942-228b9b0cc9fe.png)

I could show Anna and Nobody, excluding Bob from the view (his transactions are excluded, not in nobody)
![image](https://github.com/dawansv/gnucash-transaction-tags/assets/267163/37809e83-6c00-42b9-b27e-a2bb9fd164a5)

Here is just Anna and Nobody
![image](https://user-images.githubusercontent.com/267163/235812705-d9a8a4e5-2f4b-4ff4-97c2-b9f0b8b2920e.png)

Many more variations are possible, thanks to the wonderfull filter feature. 
