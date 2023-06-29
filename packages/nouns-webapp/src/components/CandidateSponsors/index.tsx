import React from 'react';
import { Trans } from '@lingui/macro';
import { useBlockNumber, useEthers } from '@usedapp/core';
import { useCallback, useEffect, useState } from 'react';
import { useAppDispatch } from '../../hooks';
import { AlertModal, setAlertModal } from '../../state/slices/application';
import { useProposeBySigs } from '../../wrappers/nounsData';
import { useProposalThreshold } from '../../wrappers/nounsDao';
import { ProposalCandidate } from '../../wrappers/nounsData';
import { AnimatePresence, motion } from 'framer-motion/dist/framer-motion';
import { Delegates } from '../../wrappers/subgraph';
import { useDelegateNounsAtBlockQuery, useUserVotes } from '../../wrappers/nounToken';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faCircleCheck } from '@fortawesome/free-solid-svg-icons';
import classes from './CandidateSponsors.module.css';
import Signature from './Signature';
import SignatureForm from './SignatureForm';

interface CandidateSponsorsProps {
  candidate: ProposalCandidate;
  slug: string;
  isProposer: boolean;
  id: string;
  handleRefetchCandidateData: Function;
  setDataFetchPollInterval: Function;
}

const deDupeSigners = (signers: string[]) => {
  const uniqueSigners: string[] = [];
  signers.forEach(signer => {
    if (!uniqueSigners.includes(signer)) {
      uniqueSigners.push(signer);
    }
  }
  );
  return uniqueSigners;
}

const CandidateSponsors: React.FC<CandidateSponsorsProps> = props => {
  const [signedVotes, setSignedVotes] = React.useState<number>(0);
  const [requiredVotes, setRequiredVotes] = React.useState<number>();
  const [isFormDisplayed, setIsFormDisplayed] = React.useState<boolean>(false);
  const [isAccountSigner, setIsAccountSigner] = React.useState<boolean>(false);
  const [currentBlock, setCurrentBlock] = React.useState<number>();
  const [signatures, setSignatures] = useState<any[]>([]);
  const [isCancelOverlayVisible, setIsCancelOverlayVisible] = useState<boolean>(false);
  const { account } = useEthers();
  const blockNumber = useBlockNumber();
  const connectedAccountNounVotes = useUserVotes() || 0;
  const threshold = useProposalThreshold();

  useEffect(() => {
    // prevent live-updating the block resulting in undefined block number
    if (blockNumber && !currentBlock) {
      setCurrentBlock(blockNumber);
    }
  }, [blockNumber]);
  const signers = deDupeSigners(props.candidate.version.versionSignatures?.map(signature => signature.signer.id));
  const delegateSnapshot = useDelegateNounsAtBlockQuery(signers, currentBlock || 0);
  const handleSignerCountDecrease = (decreaseAmount: number) => {
    setSignedVotes(signedVotes => signedVotes - decreaseAmount);
  };
  const filterSignersByVersion = (delegateSnapshot: Delegates) => {
    const activeSigs = props.candidate.version.versionSignatures.filter(sig => sig.canceled === false)
    let votes = 0;
    const sigs = activeSigs.map((signature, i) => {
      if (signature.expirationTimestamp < Math.round(Date.now() / 1000)) {
        activeSigs.splice(i, 1);
      }
      if (signature.signer.id.toUpperCase() === account?.toUpperCase()) {
        setIsAccountSigner(true);
      }
      delegateSnapshot.delegates?.map(delegate => {
        if (delegate.id === signature.signer.id) {
          votes += delegate.nounsRepresented.length;
        }
        return delegate;
      });
      return signature;
    });
    setSignedVotes(votes);
    return sigs;
  };

  const handleSignatureRemoved = () => {
    setIsAccountSigner(false);
    handleSignerCountDecrease(1);
  }

  useEffect(() => {
    if (threshold !== undefined) {
      setRequiredVotes(threshold + 1);
    }
  }, [threshold]);

  useEffect(() => {
    if (delegateSnapshot.data && !isCancelOverlayVisible) {
      setSignatures(filterSignersByVersion(delegateSnapshot.data));
    }
  }, [props.candidate, delegateSnapshot.data]);

  const [isProposePending, setProposePending] = useState(false);
  const dispatch = useAppDispatch();
  const setModal = useCallback((modal: AlertModal) => dispatch(setAlertModal(modal)), [dispatch]);
  const { proposeBySigs, proposeBySigsState } = useProposeBySigs();
  const [addSignatureTransactionState, setAddSignatureTransactionState] = useState<
    'None' | 'Success' | 'Mining' | 'Fail' | 'Exception'
  >('None');

  useEffect(() => {
    switch (proposeBySigsState.status) {
      case 'None':
        setProposePending(false);
        break;
      case 'Mining':
        setProposePending(true);
        props.setDataFetchPollInterval(50);
        break;
      case 'Success':
        setModal({
          title: <Trans>Success</Trans>,
          message: <Trans>Proposal Created!</Trans>,
          show: true,
        });
        setProposePending(false);
        props.handleRefetchCandidateData();
        break;
      case 'Fail':
        setModal({
          title: <Trans>Transaction Failed</Trans>,
          message: proposeBySigsState?.errorMessage || <Trans>Please try again.</Trans>,
          show: true,
        });
        setProposePending(false);
        break;
      case 'Exception':
        setModal({
          title: <Trans>Error</Trans>,
          message: proposeBySigsState?.errorMessage || <Trans>Please try again.</Trans>,
          show: true,
        });
        setProposePending(false);
        break;
    }
  }, [proposeBySigsState, setModal]);

  const submitProposalOnChain = async () => {
    await proposeBySigs(
      signatures?.map((s: any) => [s.sig, s.signer.id, s.expirationTimestamp]),
      props.candidate.version.targets,
      props.candidate.version.values,
      props.candidate.version.signatures,
      props.candidate.version.calldatas,
      props.candidate.version.description,
    );
  };

  return (
    <div className={classes.wrapper}>
      <div className={classes.interiorWrapper}>
        {requiredVotes && signedVotes >= requiredVotes && (
          <p className={classes.thresholdMet}>
            <FontAwesomeIcon icon={faCircleCheck} /> Sponsor threshold met
          </p>
        )}
        <h4 className={classes.header}>
          <strong>
            {signedVotes >= 0 ? signedVotes : '...'} of {requiredVotes || '...'} Sponsored Votes
          </strong>
        </h4>
        <p className={classes.subhead}>
          {requiredVotes && signedVotes >= requiredVotes ? (
            <Trans>
              This candidate has met the required threshold, but Nouns voters can still add support
              until it’s put on-chain.
            </Trans>
          ) : (
            <>Proposal candidates must meet the required Nouns vote threshold.</>
          )}
        </p>
        <ul className={classes.sponsorsList}>
          {signatures &&
            signatures.map(signature => {
              const voteCount = delegateSnapshot.data?.delegates?.find(
                delegate => delegate.id === signature.signer.id,
              )?.nounsRepresented.length;
              if (!voteCount) return null;
              if (signature.canceled) return null;
              return (
                <Signature
                  key={signature.signer.id}
                  reason={signature.reason}
                  voteCount={voteCount}
                  expirationTimestamp={signature.expirationTimestamp}
                  signer={signature.signer.id}
                  isAccountSigner={isAccountSigner}
                  sig={signature.sig}
                  handleSignerCountDecrease={handleSignerCountDecrease}
                  handleRefetchCandidateData={props.handleRefetchCandidateData}
                  setIsAccountSigner={setIsAccountSigner}
                  handleSignatureRemoved={handleSignatureRemoved}
                  setIsCancelOverlayVisible={setIsCancelOverlayVisible}
                />
              );
            })}
          {signatures &&
            requiredVotes &&
            signedVotes < requiredVotes &&
            Array(requiredVotes - signatures.length)
              .fill('')
              .map((_s, i) => <li className={classes.placeholder} key={i}> </li>)}

          {props.isProposer && requiredVotes && signedVotes >= requiredVotes ? (
            <button className={classes.button}
              disabled={isProposePending}
              onClick={() => submitProposalOnChain()}>
              Submit on-chain
            </button>
          ) : (
            <>
              {!isAccountSigner && (
                <>
                  {connectedAccountNounVotes > 0 ? (
                    <button
                      className={classes.button}
                      onClick={() => setIsFormDisplayed(!isFormDisplayed)}
                    >
                      Sponsor
                    </button>
                  ) : (
                    <div className={classes.withoutVotesMsg}>
                      <p>
                        <Trans>Sponsoring a proposal requires at least one Noun vote</Trans>
                      </p>
                    </div>
                  )}
                </>
              )}
            </>
          )}
        </ul>
        <AnimatePresence>
          {addSignatureTransactionState === 'Success' && (
            <div className="transactionStatus success">
              <p>Success!</p>
            </div>
          )}
          {isFormDisplayed ? (
            <motion.div
              className={classes.formOverlay}
              initial={{ opacity: 0, y: -20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              transition={{ duration: 0.15 }}
            >
              <button className={classes.closeButton} onClick={() => {
                setIsFormDisplayed(false);
                props.setDataFetchPollInterval(0);
              }}>
                &times;
              </button>
              <SignatureForm
                id={props.id}
                transactionState={addSignatureTransactionState}
                setTransactionState={setAddSignatureTransactionState}
                setIsFormDisplayed={setIsFormDisplayed}
                candidate={props.candidate}
                handleRefetchCandidateData={props.handleRefetchCandidateData}
                setDataFetchPollInterval={props.setDataFetchPollInterval}
              />
            </motion.div>
          ) : null}
        </AnimatePresence>
      </div>
      <div className={classes.aboutText}>
        <p>
          <strong><Trans>About sponsoring proposal candidates</Trans></strong>
        </p>
        <p>
          <Trans>
            Once a signed proposal is on-chain, signers will need to wait until the proposal is queued
            or defeated before putting another proposal on-chain.
          </Trans>
        </p>
      </div>
    </div>
  );
};

export default CandidateSponsors;
