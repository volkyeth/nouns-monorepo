import React, { useState } from 'react';
import classes from './CandidateSponsors.module.css';
import { CandidateSignature } from '../../wrappers/nounsData';
import CandidateSponsorImage from './CandidateSponsorImage';
import { useQuery } from '@apollo/client';
import { Delegates, delegateNounsAtBlockQuery } from '../../wrappers/subgraph';
import clsx from 'clsx';

type Props = {
  signers: CandidateSignature[];
  nounsRequired: number;
  currentBlock?: number;
};

function CandidateSponsors({ signers, nounsRequired, currentBlock }: Props) {
  const [signerSpots, setSignerSpots] = useState<CandidateSignature[]>();
  const [signerCountOverflow, setSignerCountOverflow] = useState(0);
  const signerIds = signers?.map(s => s.signer.id) ?? [];
  const { data: delegateSnapshot } = useQuery<Delegates>(
    delegateNounsAtBlockQuery(signerIds ?? [], currentBlock ?? 0),
  );
  const { delegates } = delegateSnapshot || {};
  const delegateToNounIds = delegates?.reduce<Record<string, string[]>>((acc, curr) => {
    acc[curr.id] = curr?.nounsRepresented?.map(nr => nr.id) ?? [];
    return acc;
  }, {});
  const nounIds = Object.values(delegateToNounIds ?? {}).flat();
  React.useEffect(() => {
    if (signers && signers.length < nounsRequired) {
      setSignerSpots(signers);
    } else if (signers && signers.length > nounsRequired) {
      setSignerCountOverflow(signers.length - nounsRequired);
      setSignerSpots(signers.slice(0, nounsRequired || 3));
    } else {
      setSignerSpots(signers);
    }
  }, [signers, nounsRequired]);

  const placeholderCount = nounsRequired - signers.length;
  const placeholderArray = Array(placeholderCount >= 1 ? placeholderCount : 0).fill(0);
  return (
    <div className={clsx(classes.sponsorsWrap,
      signerCountOverflow > 0 && classes.sponsorsWrapOverflow,
    )}>
      <div className={classes.sponsors}>
        {signerSpots &&
          signerSpots.length > 0 &&
          delegateToNounIds &&
          nounIds.map((nounId, i) => {
            return (
              <CandidateSponsorImage nounId={+nounId} key={i} />
            );
          })}
      </div>
      {placeholderArray.map((_) => (
        <div className={classes.emptySponsorSpot} />
      ))}
    </div>
  );
}

export default CandidateSponsors;
